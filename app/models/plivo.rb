# -*- coding: utf-8 -*-
class PlivoCannotCall < Exception
end

class PlivoChannelFull < Exception
end

class PlivoNotFound < Exception
end


class Plivo < ActiveRecord::Base
  attr_accessible :app_url, :api_url, :auth_token, :campaign_id, :sid, :status, :gateways, :caller_name, :gateway_timeouts, :gateway_retries, :gateway_codecs, :channels, :phonenumber
  belongs_to :campaign
  has_many :plivo_call

  validates :app_url, :api_url, :sid, :auth_token, :campaign_id, :gateways, :gateway_timeouts, :gateway_retries, :caller_name, :presence => true
  validates :channels, :numericality => true
  validates :gateway_retries, :gateway_timeouts, :numericality => true

  before_save :verificar_conexion

  #Realiza prueba de conexion
  #al servidor plivo
  def verificar_conexion
    begin
      plivor = PlivoHelper::Rest.new(self.api_url, self.sid, self.auth_token)
      extra_dial_string = "leg_delay_start=1,bridge_early_media=true,hangup_after_bridge=true" 
      call_params = {
        'From' => self.caller_name,
        'To' => '',
        'Gateways' => self.gateways,
        'GatewayCodecs' => self.gateway_codecs,
        'GatewayTimeouts' => self.gateway_timeouts,
        'GatewayRetries' => self.gateway_retries,
        #'AnswerUrl' => answer_client_self_url(),
        #'HangupUrl' => hangup_client_self_url(),
        #'RingUrl' => ringing_client_self_url()
        'ExtraDialString' => extra_dial_string,
        'AnswerUrl' => "%s/0/answer_client" % self.app_url,
        'HangupUrl' => "%s/selfs/0/hangup_client" % self.app_url,
        'RingUrl' => "%s/selfs/0/ringing_client" % self.app_url
      }
      result = ActiveSupport::JSON.decode(plivor.call(call_params).body)
    rescue Errno::ECONNREFUSED => e
      errors.add(:api_url, "Conexion rechazada")
      return false
    rescue Exception => e
      errors.add(:sid, "Fallo autenticación")
      errors.add(:auth_token, "Fallo autenticación")
      errors.add(:api_url, e)
      return false
    end

    return true
  end

  
  
  #Encommila la cadena de los codecs
  def gateway_codecs_quote
    return "'%s'" % gateway_codecs
  end

  def status
    return verificar_conexion ? "Conectado" : "Desconectado"
  end

  #pregunta si puede llamara
  #en caso de estar todas los canales ocupados se retorna no
  def can_call?
    using_channels = PlivoCall.where(:end => false).count()
    #logger.debug("Channels %d for plivo %s and now using %s" % [channels, caller_name, using_channels])
    return false if using_channels >= channels
    return true
  end
  


  #LLamar con el mensaje al cliente
  #@throw PlivoCannotCall
  def call_client(client, message, message_calendar = nil)
    raise PlivoChannelFull, "No hay canales disponibles" unless can_call?
   
    #http://wiki.freeswitch.org/wiki/Channel_Variables#monitor_early_media_ring
    extra_dial_string = "leg_delay_start=1,bridge_early_media=true,hangup_after_bridge=true" 
    if message.hangup_on_ring > 0
      extra_dial_string += 'leg_timeout=%d' % message.hangup_on_ring
    end
    
    call_params = {
      'From' => self.phonenumber,
      'CallerName' => self.caller_name,
      'To' => client.phonenumber,
      'Gateways' => self.gateways,
      'GatewayCodecs' => self.gateway_codecs_quote,
      'GatewayTimeouts' => self.gateway_timeouts,
      'GatewayRetries' => self.gateway_retries,
      'ExtraDialString' => extra_dial_string,
      'AnswerUrl' => "%s/plivos/0/answer_client" % self.app_url,
      'HangupUrl' => "%s/plivos/0/hangup_client" % self.app_url,
      'RingUrl' => "%s/plivos/0/ringing_client" % self.app_url,
      
    }

    if message.time_limit > 0
      call_params['TimeLimit'] = message.time_limit.to_i
    end

    if message.hangup_on_ring > 0
      #NO FUNCIONA
      #call_params['HangupOnRing'] = message.hangup_on_ring
    end

    call = Call.new
    call.message_id = message.id
    call.client_id = client.id
    call.length = 0
    call.completed_p = false
    call.enter = Time.now
    call.terminate = nil
    call.enter_listen = nil
    call.terminate_listen = nil
    call.status = 'calling'
    call.hangup_enumeration = nil
    call.message_calendar_id = message_calendar.id unless message_calendar.nil?
    call.save

    sequence = message.description_to_call_sequence('!client_fullname' => client.fullname, '!client_id' => client.id)
    #Se registra la llamada iniciada de plivo
    plivocall = PlivoCall.new
    plivocall.number = client.phonenumber
    plivocall.plivo_id = id
    plivocall.uuid = ''
    plivocall.status = 'calling'
    plivocall.hangup_enumeration = nil
    plivocall.data = sequence.to_yaml
    plivocall.call_id = call.id
    plivocall.end = false
    plivocall.step = 0
    plivocall.save
    call_params['AccountSID'] = plivocall.id
    logger.debug(call_params)      
    
    #@todo ERROR OCURRE ERROR..SE ENVIA LA LLAMA Y PLIVO RESPONDE DEMASIADO RAPIDO
    #INCLUSIVE ANTES DE GUARDAR LOS REGISTROS
    #PARA MANTENER NUESTRO PROPIO ID utilizamaos el parametro AccountSID de plivo
    plivor = PlivoHelper::Rest.new(self.api_url, self.sid, self.auth_token)
    result = ActiveSupport::JSON.decode(plivor.call(call_params).body)
    logger.error(result)
    if result["Success"]
      plivocall.uuid = result["RequestUUID"]
      plivocall.save
      return true
    else
      plivocall.destroy
      return false
    end
  end
 
  #@todo CAMBIAR COMO ARRIBA
  def call_clients(clients, message)
    return false if clients.empty?
    tos = []
    delimiter = ';'
    bgateways = []
    bgateways_timeout = []
    bgateways_codecs = []
    bgateways_retries = []
    clients.each do |client, message_calendar|
      tos << client.phonenumber
      bgateways << self.gateways
      bgateways_codecs << self.gateway_codecs_quote
      bgateways_timeout << self.gateway_timeouts
      bgateways_retries << self.gateway_retries
    end
    extra_dial_string = "leg_delay_start=1,bridge_early_media=true,hangup_after_bridge=true" 
    if message.hangup_on_ring > 0
      extra_dial_string += 'leg_timeout=%d' % message.hangup_on_ring
    end

    call_params = {
      'Delimiter' => delimiter,
      'From' => self.phonenumber,
      'CallerName' => self.caller_name,
      'To' => tos.join(delimiter),
      'Gateways' => bgateways.join(delimiter),
      'GatewayCodecs' => bgateways_codecs.join(delimiter),
      'GatewayTimeouts' => bgateways_timeout.join(delimiter),
      'GatewayRetries' => bgateways_retries.join(delimiter),
      'ExtraDialString' => extra_dial_string,
      'AnswerUrl' => "%s/plivos/0/answer_client" % self.app_url,
      'HangupUrl' => "%s/plivos/0/hangup_client" % self.app_url,
      'RingUrl' => "%s/plivos/0/ringing_client" % self.app_url,
    }
    logger.debug(call_params)


    plivor = PlivoHelper::Rest.new(self.api_url, self.sid, self.auth_token)
    result = ActiveSupport::JSON.decode(plivor.bulk_call(call_params).body)
    #unless result["Success"]
    #  self.unlock_calling
     # return false
    #end
    
    logger.debug(result)
    result[:RequestUUId].each_index do |index|
      uuid = result[:RequestUUId][index]
      client = clients[index][0]
      #message = clients[index][1]
      message_calendar = clients[index][1]
      #se registra llamada
      call = Call.new
      call.message_id = message.id
      call.client_id = client.id
      call.length = 0
      call.completed_p = false
      call.enter = Time.now
      call.terminate = nil
      call.enter_listen = nil
      call.terminate_listen = nil
      call.status = 'calling'
      call.hangup_enumeration = nil
      call.message_calendar_id = message_calendar.id unless message_calendar.nil?
      call.save
      
      sequence = message.description_to_call_sequence('!client_fullname' => client.fullname, '!client_id' => client.id)
      #Se registra la llamada iniciada de plivo
      plivocall = PlivoCall.where(:uuid => uuid).first_or_initialize
      plivocall.number = client.phonenumber
      plivocall.plivo_id = id
      plivocall.uuid = uuid
      plivocall.status = 'calling'
      plivocall.hangup_enumeration = nil
      plivocall.data = sequence.to_yaml
      plivocall.call_id = call.id
      plivocall.end = false
      plivocall.step = 0
      plivocall.save
    end
  end
end
