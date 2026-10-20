require_relative "../../spec_helper.rb"

describe Ropensci::SeekingReviewersResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    params = { template_file: "badge.md", add_labels: ["1/editor-checks"], remove_labels: ["2/seeking-reviewer(s)"] }

    @responder = subject.new(settings, params)
    disable_github_calls_for(@responder)
    @cmd = "@ropensci-review-bot seeking reviewers"
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot seeking reviewers")
      expect(@responder.event_regex).to match("@ropensci-review-bot seeking reviewers.")
      expect(@responder.event_regex).to match("@ropensci-review-bot seeking reviewers  \r\n")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot seeking reviewers. another-command")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot seeking reviewers\r\nanother-command")
    end
  end

  describe "#records_data" do

  end

  describe "#process_message" do
    before do
      @responder.context = OpenStruct.new(issue_id: 15,
                                          issue_author: "opener",
                                          repo: "ropensci/test-submissions",
                                          sender: "rev33",
                                          issue_body: "Test Submission\n\n ... description ... \n\n" +
                                                      "<!--author1-->@first_author<!--end-author1-->\n" +
                                                      "<!--author-others-->@second_author, @third_author<!--end-author-others-->\n" +
                                                      "<!--repourl-->https://github.com/ropensci-packages/great-package<!--end-repourl-->\n" +
                                                      "Editor: <!--editor-->@editor33<!--end-editor-->",
                                          raw_payload: { "issue" => {"created_at" => "2021-09-06T11:08:23Z"}}
                                          )
    end

    it "should respond configured template" do
      expect(@responder).to receive(:render_external_template).
                            with("badge.md", @responder.locals).
                            and_return("next steps")
      expect(@responder).to receive(:respond).with("next steps")

      @responder.process_message(@cmd)
    end

    it "should create records_data" do
      expected_data = {
        author1: "first_author",
        author_others: ["second_author", "third_author"],
        submission_url: "https://github.com/ropensci/test-submissions/issues/15",
        repo_url: "https://github.com/ropensci-packages/great-package",
        package_name: "great-package",
        editor: "editor33",
        submitted_at: "2021-09-06T11:08:23Z"
      }
      expect(@responder.records_data).to eq(expected_data)
    end

    it "should not process external call" do
      expect(@responder).to_not receive(:process_external_service)
      @responder.params = { command: "do something" }
      @responder.process_message("@botsci do something")
    end

    it "should process labeling" do
      @responder.params[:template_file] = nil
      expect(@responder).to receive(:process_labeling)
      @responder.process_message(@cmd)
    end
  end

end