module Ropensci
  class OnHoldReminderWorker < BuffyWorker

    def perform(locals, params)
      load_context_and_env(locals)
      reminder_params = OpenStruct.new(params)

      return false if issue.state == "closed"
      return false unless issue_labels.include?(reminder_params.on_hold_label)

      respond("@#{context.sender}: Please review the holding status")
    end
  end
end
