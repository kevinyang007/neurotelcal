# -*- coding: utf-8 -*-
require 'csv'

class ReportsController < ApplicationController
  def index
    @calls = Call.paginate :page => params[:page], :order => 'created_at DESC'
    @report = {:general => {}}
    #por estado de cuelgue
    @report[:general][:by_hangup_enumeration] = Call.group(:hangup_enumeration).count


    #estadisticos
    @report[:general][:statistical] = {
      :response_ivr => PlivoCall.where('data LIKE "%%result%%"').count,
      :calls_completed => PlivoCall.count
    }
    
  end

  def export_csv_index
    csv_string = CSV.generate do |csv|
      csv << ["Entidad", "Campaña", "Client", "Mensaje", "Programado para", "LLamada inicio", "Llamada finalizo", "Contesta inicio", "Contesta finalizo", "Duración", "Estado Final"]
      Call.find_each  do |call|
        #no se exporta los mensajes anonimos
        next if call.message.nil?
        begin
          csv << [call.message.group.campaign.entity.name, call.message.group.campaign.name, call.client.fullname, call.message.name, call.message.call, call.enter, call.terminate, call.enter_listen, call.terminate_listen, call.length,  call.hangup_status]
        rescue
        end
        
      end

    end
    
    send_data csv_string, :type => "text/csv", :filename => "export_#{session.object_id}.csv", :disposition => 'attachment'
  end

end
