require_relative '../../lib/responder'

module Ropensci
  class ApproveResponder < Responder
    keyname :ropensci_approve

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} approve( [ \w-]+)?\.?\s*\z/i
    end

    def process_message(message)
      return unless verify_package_name
      return unless verify_submission_type

      update_or_add_value("date-accepted", Time.now.strftime("%Y-%m-%d"), append: false, heading: "Date accepted")
      respond_external_template(params[:template_file], locals) if params[:template_file]
      Ropensci::AirtableWorker.perform_async(:clear_assignments, params, locals, { reviewers: list_of_reviewers })
      process_labeling
      close_issue
    end

    def verify_package_name
      @package_name = match_data[1].to_s.strip
      if @package_name.empty?
        respond("Could not approve. Please, specify the name of the package.")
        return false
      end
      true
    end

    def verify_submission_type
      submission_type = read_value_from_body("submission-type").downcase
      if submission_type == "stats"
        statsgrade = read_value_from_body("statsgrade").downcase
        if ["bronze", "silver", "gold"].include?(statsgrade)
          labels_to_add << "6/approved-#{statsgrade}"
        else
          respond("Please add a grade (bronze/silver/gold) before approval.")
          return false
        end
      end
      true
    end

    def list_of_reviewers
      @list_of_reviewers ||= read_value_from_body("reviewers-list").split(",").map(&:strip)
    end

    def description
      "Approves a package. This command will close the issue."
    end

    def example_invocation
      "@#{@bot_name} approve package-name"
    end
  end
end
