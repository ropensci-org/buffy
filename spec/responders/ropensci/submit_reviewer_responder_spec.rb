require_relative "../../spec_helper.rb"

describe Ropensci::SubmitReviewResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    params = { all_reviews_label: "4/review-in-awaiting-changes" }
    @responder = subject.new(settings, params)
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ropensci/software-review/issues/455#issuecomment-928885183 time 7")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 10.6")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 10.6h")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 10.6 h")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 10.6 hours")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 1 hour.")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 10,6 \r\n")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit review https://github.com/ time 10:56")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot submit review time")
      expect(@responder.event_regex).to_not match("@wrong-bot submit review https://github.com 9.5")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot msubmit review https://github.com 9.5 another-command")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot submit review https://github.com time 9.5\r\nanother-command")
    end
  end

  describe "#process_message" do
    before do
      @issue_body = "... <!--reviewers-list-->@reviewer1, @reviewer2<!--end-reviewers-list--> ..."
      @valid_comment_url = "https://github.com/ropensci/testing/issues/32#issuecomment-12345678"

      disable_github_calls_for(@responder)
      allow(@responder).to receive(:issue_body).and_return(@issue_body)
      @responder.context = OpenStruct.new(issue_id: 32,
                                          issue_author: "opener",
                                          repo: "ropensci/testing",
                                          sender: "xuanxu")
    end

    it "should check for invalid time format" do
      msg = message_with("url", "10:45")
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to receive(:respond).with("Error: Invalid time format")
      @responder.process_message(msg)

      msg = message_with("url", "10.5")
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to_not receive(:respond).with("Error: Invalid time format")
      @responder.process_message(msg)
    end

    it "should verify url is valid" do
      msg = message_with("invalid-url", "10.5")
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to receive(:respond).with("Error: That url is invalid")
      @responder.process_message(msg)

      msg = message_with(@valid_comment_url, "10.5")
      allow(@responder).to receive(:issue_comment).and_raise(Octokit::NotFound)
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to_not receive(:respond).with("Error: That url is invalid")
      @responder.process_message(msg)
    end

    it "should error if comment not found" do
      allow(@responder).to receive(:issue_comment).and_raise(Octokit::NotFound)
      msg = message_with(@valid_comment_url, "10.5")
      @responder.match_data = @responder.event_regex.match(msg)

      expect(@responder).to receive(:respond).with("Error: That url is not pointing to a reviewer comment in this issue")

      @responder.process_message(msg)
    end

    it "should trigger an AirtableWorker with proper info" do
      msg = message_with(@valid_comment_url, "10.5")
      comment_created_at = Time.now
      comment = double(created_at: comment_created_at, user: double(login: "reviewer1"))
      expected_params = {all_reviews_label: "4/review-in-awaiting-changes"}
      expected_locals = {bot_name: "ropensci-review-bot", issue_author: "opener", issue_id: 32, repo: "ropensci/testing", sender: "xuanxu"}
      expected_review_data = { reviewer: "reviewer1", review_date: comment_created_at, review_time: "10.5", review_url: @valid_comment_url, reviewers: "@reviewer1, @reviewer2" }

      @responder.match_data = @responder.event_regex.match(msg)
      expect(Ropensci::AirtableWorker).to receive(:perform_async).with(:submit_review,
                                                                       expected_params,
                                                                       expected_locals,
                                                                       expected_review_data)
      expect(@responder).to receive(:issue_comment).and_return(comment)
      expect(@responder).to_not receive(:respond)

      @responder.process_message(msg)
    end
  end

  def message_with(url, time)
    "@ropensci-review-bot submit review #{url} time #{time}"
  end
end