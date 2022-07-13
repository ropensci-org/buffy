require_relative '../../lib/responder'

module Ropensci
  class OnHoldResponder < Responder

    keyname :ropensci_on_hold

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} put on hold\.?\s*\z/i
    end

    def process_message(message)
      label_issue([on_hold_label])
      Ropensci::OnHoldReminderWorker.perform_at(reminder_at, locals, {"on_hold_label" => on_hold_label})
      respond("Submission on hold!")
    end

    def on_hold_label
      params[:on_hold_label] || "holding"
    end

    def on_hold_days
      if params[:on_hold_days]
        params[:on_hold_days].to_i
      else
        90
      end
    end

    def reminder_at
      Time.now + (on_hold_days * 86400)
    end

    def default_description
      "Put the submission on hold for the next #{on_hold_days} days"
    end

    def default_example_invocation
      "@#{bot_name} put on hold"
    end
  end
end
