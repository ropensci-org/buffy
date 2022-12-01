require_relative '../../lib/responder'
require 'uri'

module Ropensci
  class SeekingReviewersResponder < Responder

    keyname :ropensci_seeking_reviewers

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} seeking reviewers\.?\s*\z/i
    end

    def process_message(message)
      respond_external_template(params[:template_file], locals) if params[:template_file]
      Ropensci::AirtableWorker.perform_async("package_and_authors", serializable(params), serializable(locals), serializable(records_data))
      process_labeling
    end

    def records_data
      author1 = user_login(read_value_from_body("author1"))
      author_others = read_value_from_body("author-others").split(",").map(&:strip) - [""]
      author_others = author_others.map {|ao| user_login(ao)}

      submission_url = "https://github.com/#{locals[:repo]}/issues/#{locals[:issue_id]}"
      repo_url = read_value_from_body("repourl")
      package_name = (URI.parse(repo_url).path.split("/")-[""])[1]
      editor = user_login(read_value_from_body("editor"))
      submitted_at = context.raw_payload.dig("issue", "created_at")

      {
        author1: author1,
        author_others: author_others,
        submission_url: submission_url,
        repo_url: repo_url,
        package_name: package_name,
        editor: editor,
        submitted_at: submitted_at
      }
    end

    def default_description
      "Switch to 'seeking reviewers'"
    end

    def default_example_invocation
      "@#{bot_name} seeking reviewers"
    end
  end
end
