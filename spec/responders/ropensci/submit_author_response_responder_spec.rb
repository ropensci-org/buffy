require_relative "../../spec_helper.rb"

describe Ropensci::SubmitAuthorResponseResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    params ={}
    @responder = subject.new(settings, params)
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot submit response https://github.com/ropensci/software-review/issues/455#issuecomment-942776103")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit response https://github.com/")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit response https://github.com/  ")
      expect(@responder.event_regex).to match("@ropensci-review-bot submit response https://github.com \r\n")
      expect(@responder.event_regex).to_not match("@wrong-bot submit submit response https://github.com")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot submit response https://github.com another-command")
    end
  end

  describe "#process_message" do
    before do
      @issue_body = "... <!--reviewers-list-->@reviewer1, @reviewer2<!--end-reviewers-list--> ..." +
                    "... <!--author1-->@first-author<!--end-author1-->" +
                    "<!--author-others-->@otherauthor, @last_author<!--end-author-others-->..." +
                    "<!--repourl-->https://github.com/scientific/test-software<!--end-repourl-->"
      @valid_comment_url = "https://github.com/ropensci/testing/issues/32#issuecomment-12345678"

      disable_github_calls_for(@responder)
      allow(@responder).to receive(:issue_body).and_return(@issue_body)
      @responder.context = OpenStruct.new(issue_id: 32,
                                          issue_author: "opener",
                                          issue_title: "Issue 1 title",
                                          repo: "ropensci/testing",
                                          sender: "author1")
    end

    it "should verify url is valid" do
      msg = message_with("invalid-url")
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to receive(:respond).with("Error: That url is invalid")
      @responder.process_message(msg)

      msg = message_with(@valid_comment_url)
      allow(@responder).to receive(:issue_comment).and_raise(Octokit::NotFound)
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to_not receive(:respond).with("Error: That url is invalid")
      @responder.process_message(msg)
    end

    it "should error if comment not found" do
      allow(@responder).to receive(:issue_comment).and_raise(Octokit::NotFound)
      msg = message_with(@valid_comment_url)
      @responder.match_data = @responder.event_regex.match(msg)

      expect(@responder).to receive(:respond).with("Error: That url is not pointing to an author comment in this issue")

      @responder.process_message(msg)
    end

    it "should trigger an AirtableWorker with proper info" do
      msg = message_with(@valid_comment_url)
      comment_created_at = Time.now
      comment = double(created_at: comment_created_at, user: double(login: "reviewer1"))
      expected_params = {}
      expected_locals = { "bot_name" => "ropensci-review-bot",
                          "issue_author" => "opener",
                          "issue_title" => "Issue 1 title",
                          "issue_id" => 32,
                          "repo" => "ropensci/testing",
                          "sender" => "author1",
                          "match_data_1" => @valid_comment_url
                        }
      expected_data = { "author_response_id" => "test-software 12345678",
                        "author_response_url" => "https://github.com/ropensci/testing/issues/32#issuecomment-12345678",
                        "submitting_date" => Time.now.strftime("%Y-%m-%d"),
                        "package_name" => "test-software" }

      @responder.match_data = @responder.event_regex.match(msg)
      expect(Ropensci::AirtableWorker).to receive(:perform_async).with("submit_author_response",
                                                                       expected_params,
                                                                       expected_locals,
                                                                       expected_data)
      expect(@responder).to receive(:issue_comment).and_return(comment)
      expect(@responder).to_not receive(:respond)

      @responder.process_message(msg)
    end
  end

  def message_with(url)
    "@ropensci-review-bot submit response #{url}"
  end
end