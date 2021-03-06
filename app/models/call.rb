class Call < ActiveRecord::Base
  attr_accessible :client_id, :completed_p, :length, :message_id, :enter, :terminate, :hangup_enumeration, :status, :enter_listen, :terminate_listen, :bill_duration
  attr_accessible :data, :digits, :created_at, :id, :updated_at, :client
  attr_accessible :message_calendar_id
  attr_accessible :plivo_call
  belongs_to :message
  belongs_to :client
  has_one :plivo_call

  scope :done_calls_message, lambda {|message_id| where(:message_id => message_id, :hangup_enumeration => PlivoCall::ANSWER_ENUMERATION)}
  scope :done_calls_message_client?, lambda {|message_id, client_id| where(:message_id => message_id, :client_id => client_id, :hangup_enumeration => PlivoCall::ANSWER_ENUMERATION)}
  scope :not_answered_for_message_client, lambda{|message_id, client_id| where(:message_id => message_id, :client_id => client_id).where("hangup_enumeration NOT IN(?)", PlivoCall::ANSWER_ENUMERATION)}
  scope :in_process_for_client?, lambda {|client_id| where(:client_id => client_id, :terminate => nil)}
  scope :in_process_for_message_client?, lambda {|message_id, client_id| where(:message_id => message_id, :client_id => client_id, :terminate => nil)}
  scope :in_process_for_message, lambda {|message_id| where(:message_id => message_id, :terminate => nil)}
  scope :answered_for_client?, lambda{|client_id| where(:client_id => client_id).where(:hangup_enumeration => PlivoCall::ANSWER_ENUMERATION)}
  scope :answered_for_message, lambda{|message_id| where(:message_id => message_id, :hangup_enumeration => PlivoCall::ANSWER_ENUMERATION)}
  scope :answered_for_message_calendar, lambda{|message_calendar_id| where(:message_calendar_id => message_calendar_id, :hangup_enumeration => PlivoCall::ANSWER_ENUMERATION)}
  #Retorna estado de c
  def hangup_status
    case self.hangup_enumeration
    when 'USER_BUSY'
      return I18n.t('call.hangup_status.user_busy')
    when 'SUBSCRIBER_ABSENT'
      return I18n.t('call.hangup_status.subscriber_absent')
    when 'CALL_REJECTED'
      return I18n.t('call.hangup_status.call_rejected')
    when 'NORMAL_CLEARING'
      return I18n.t('call.hangup_status.normal_clearing')
    when 'NO_ANSWER'
      return I18n.t('call.hangup_status.no_answer')
    when 'UNALLOCATED_NUMBER'
      return I18n.t('call.hangup_status.unallocated_number')
    else
      return self.hangup_enumeration
    end
  end

  def answered?
    return self.hangup_enumeration == 'NORMAL_CLEARING'
  end

  
   
end
