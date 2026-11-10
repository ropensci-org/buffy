require_relative "../../spec_helper.rb"

describe Ropensci::OnHoldReminderWorker do
  before do
    @worker = described_class.new
    disable_github_calls_for(@worker)
  end

  describe "perform" do
    before do
      @locals = { issue_id: 33,
                  issue_author: "author",
                  repo: "ropensci/reviews",
                  sender: "editor",
                  bot_name: "ropensci-review-bot" }

      @params = { "on_hold_label" => "holding"}
    end

    it "should do nothing if issue is closed" do
      expect(@worker).to receive(:issue).and_return(double(state: "closed"))
      expect(@worker).to_not receive(:respond)

      @worker.perform(@locals, @params)
    end

    it "should do nothing if holding label is not present" do
      expect(@worker).to receive(:issue).and_return(double(state: "open"))
      expect(@worker).to receive(:issue_labels).and_return(["approved"])
      expect(@worker).to_not receive(:respond)

      @worker.perform(@locals, @params)
    end

    it "should reply reminder" do
      expect(@worker).to receive(:issue).and_return(double(state: "open"))
      expect(@worker).to receive(:issue_labels).and_return(["holding"])

      expected_reply = "@editor: Please review the holding status"
      expect(@worker).to receive(:respond).with(expected_reply)

      @worker.perform(@locals, @params)
    end
  end
end
