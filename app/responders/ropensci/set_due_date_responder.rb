require_relative '../../lib/responder'
require 'chronic'

module Ropensci
  class SetDueDateResponder < Responder

    keyname :ropensci_set_due_date

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} set due date for (\S+) to:? (\S*)\s*\z/i
    end

    def process_message(message)
      reviewer = @match_data[1]
      due_date = @match_data[2].strip

      if !issue_body_has?("reviewers-list")
        respond("I can't find the reviewers list")
        return
      end

      unless due_date.match?(/\d\d\d\d-\d\d-\d\d/)
        respond("Wrong due date format, please use: `YYYY-MM-DD`")
        return
      end

      unless list_of_reviewers.include?(reviewer)
        respond("Can't set due date: #{reviewer} is not included in the reviewers list")
        return
      end

      new_due_date = Chronic.parse(due_date)
      if new_due_date.to_date < Date.today
        respond("Can't set due date: #{new_due_date.strftime('%d/%B/%Y')} is in the past")
        return
      end

      list = list_of_due_dates.delete_if {|entry| entry.match?(/^Due date for #{reviewer}:/)}
      list << "Due date for #{reviewer}: #{new_due_date.strftime('%Y-%m-%d')}"

      update_list("due-dates", list.join("\n"))
      respond("Review due date for #{reviewer} is now #{new_due_date.strftime('%d-%B-%Y')}")
    end

    def list_of_reviewers
      @list_of_reviewers ||= read_value_from_body("reviewers-list").split(",").map(&:strip)
    end

    def list_of_due_dates
      @list_of_due_dates ||= read_value_from_body("due-dates-list").strip.split("\n").map(&:strip)
    end

    def description
      "Change or add a review's due date for a reviewer"
    end

    def example_invocation
      "@#{@bot_name} set due date for @reviewer to YYYY-MM-DD"
    end
  end
end

