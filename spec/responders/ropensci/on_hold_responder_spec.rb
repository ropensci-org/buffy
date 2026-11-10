require_relative "../../spec_helper.rb"

describe Ropensci::OnHoldResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    @responder = subject.new(settings, {})
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot put on hold")
      expect(@responder.event_regex).to match("@ropensci-review-bot put on hold  \r\n")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot put on hold. More text")
    end
  end

  describe "#process_message" do
    before do
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 32,
                                          issue_author: "the-author",
                                          issue_title: "A new issue",
                                          repo: "openjournals/testing",
                                          sender: "the-editor")
      @msg = "@ropensci-review-bot put on hold"
    end

    it "should label issue" do
      expect(@responder).to receive(:label_issue).with(["holding"])
      @responder.process_message(@msg)
    end

    it "should label issue with custom label" do
      @responder.params[:on_hold_label] = "submission-paused"
      expect(@responder).to_not receive(:label_issue).with(["holding"])
      expect(@responder).to receive(:label_issue).with(["submission-paused"])
      @responder.process_message(@msg)
    end

    it "should respond to github" do
      expect(@responder).to receive(:respond).with("Submission on hold!")
      @responder.process_message(@msg)
    end

    it "should create a OnHoldReminderWorker with correct info" do
      time_now = Time.now
      expect(Time).to receive(:now).and_return(time_now)

      expected_params = { "on_hold_label" => "holding"}
      expected_locals = {"bot_name"=>"ropensci-review-bot", "issue_author"=>"the-author", "issue_title"=>"A new issue", "issue_id"=>32, "repo"=>"openjournals/testing", "sender"=>"the-editor"}
      expected_time = time_now + (90 * 86400)

      expect(Ropensci::OnHoldReminderWorker).to receive(:perform_at).with(expected_time, expected_locals, expected_params)
      @responder.process_message(@msg)
    end

    it "should create a OnHoldReminderWorker to run at a custom time" do
      @responder.params[:on_hold_days] = 27

      time_now = Time.now
      expect(Time).to receive(:now).and_return(time_now)

      expected_params = { "on_hold_label" => "holding"}
      expected_locals = {"bot_name"=>"ropensci-review-bot", "issue_author"=>"the-author", "issue_title"=>"A new issue", "issue_id"=>32, "repo"=>"openjournals/testing", "sender"=>"the-editor"}
      expected_time = time_now + (27 * 86400)

      expect(Ropensci::OnHoldReminderWorker).to receive(:perform_at).with(expected_time, expected_locals, expected_params)
      @responder.process_message(@msg)
    end
  end
end