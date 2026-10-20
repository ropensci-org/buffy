require_relative '../../lib/responder'

module Ropensci
  class SubmitAuthorResponseResponder < Responder

    keyname :ropensci_submit_author_response

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} submit response (\S+)\s*\z/i
    end

    def process_message(message)
      author_response_url = @match_data[1]

      if author_response_url.match?(/#{issue_url}#issuecomment-(\d+)/)
        issue_comment_id = author_response_url.match(/#{issue_url}#issuecomment-(\d+)/)[1]
      else
        respond("Error: That url is invalid")
        return
      end

      begin
        comment = issue_comment(issue_comment_id)
      rescue Octokit::NotFound
        respond("Error: That url is not pointing to an author comment in this issue")
        return
      end

      repo_url = read_value_from_body("repourl")
      package_name = (URI.parse(repo_url).path.split("/")-[""])[1]

      author_response_data = { author_response_id: "#{package_name} #{issue_comment_id}",
                               author_response_url: author_response_url,
                               submitting_date: Time.now.strftime("%Y-%m-%d"),
                               package_name: package_name }
      Ropensci::AirtableWorker.perform_async("submit_author_response", serializable(params), serializable(locals), serializable(author_response_data))
    end

    def default_description
      "Add an author's response info to the ROpenSci logs"
    end

    def default_example_invocation
      "@#{@bot_name} submit response <AUTHOR_RESPONSE_URL>"
    end
  end
end