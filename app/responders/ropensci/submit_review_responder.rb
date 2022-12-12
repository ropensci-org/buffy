require_relative '../../lib/responder'

module Ropensci
  class SubmitReviewResponder < Responder

    keyname :ropensci_submit_reviews

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} submit review (\S+) time ([\d.,:]+|NA)+\s?(h|hour|hours)?\.?\s*\z/i
    end

    def process_message(message)
      review_url = @match_data[1]
      review_time = @match_data[2].to_s.gsub(",", ".")

      if review_time.include?(":")
        respond("Error: Invalid time format")
        return
      end

      if review_url.match?(/#{issue_url}#issuecomment-(\d+)/)
        issue_comment_id = review_url.match(/#{issue_url}#issuecomment-(\d+)/)[1]
      else
        respond("Error: That url is invalid")
        return
      end

      begin
        comment = issue_comment(issue_comment_id)
      rescue Octokit::NotFound
        respond("Error: That url is not pointing to a reviewer comment in this issue")
        return
      end

      reviewers = read_value_from_body("reviewers-list")
      repo_url = read_value_from_body("repourl")
      package_name = (URI.parse(repo_url).path.split("/")-[""])[1]

      comment_date = comment.created_at
      reviewer = comment.user.login

      review_data = { reviewer: reviewer,
                      review_date: comment_date,
                      review_time: review_time,
                      review_url: review_url,
                      reviewers: reviewers,
                      package_name: package_name
                    }
      Ropensci::AirtableWorker.perform_async("submit_review", serializable(params), serializable(locals), serializable(review_data))
    end

    def default_description
      "Add a review's info to the ROpenSci logs"
    end

    def default_example_invocation
      "@#{@bot_name} submit review <REVIEW_URL> time <REVIEW_HOURS(ex. 10.5)>"
    end
  end
end
