require 'date'

module Ropensci
  class ReminderReviewDeadlineWorker < BuffyWorker

    def perform(locals, params)
      load_context_and_env(locals)
      reminder_params = OpenStruct.new(params)

      return false if issue.state == "closed"
      return false if reminder_params.template_file.nil?

      current_due_date = due_date_for(reminder_params.reviewer)

      if current_due_date && Date.today + reminder_params.days_before_deadline.to_i == current_due_date
        info = { reviewer: reminder_params.reviewer,
                 days_before_deadline: reminder_params.days_before_deadline,
                 due_date: current_due_date.strftime('%Y-%m-%d') }

        respond_external_template(reminder_params.template_file, info)
      end
    end

    def due_date_for(reviewer)
      @list_of_due_dates ||= read_value_from_body("due-dates-list").strip.split("\n").map(&:strip)

      entry = @list_of_due_dates.select {|entry| entry.match?(/^Due date for #{reviewer}:/)}.first
      return nil if entry.nil?

      due_date_string = /^Due date for #{reviewer}: ([\d-]+)/.match(entry)[1]
      return nil if due_date.nil?

      Date.parse(due_date_string)
    end
  end
end
