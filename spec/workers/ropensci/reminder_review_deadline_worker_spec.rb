require_relative "../../spec_helper.rb"

describe Ropensci::ReminderReviewDeadlineWorker do
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

      @params = { days_before_deadline: 2, template_file: "reminder.md", reviewer: "@reviewer33"}
    end
    it "should do nothing if issue is closed" do
      expect(@worker).to receive(:issue).and_return(double(state: "closed"))
      expect(@worker).to_not receive(:respond_external_template)

      @worker.perform(@locals, @params)
    end

    it "should do nothing if no reply template configured" do
      expect(@worker).to receive(:issue).and_return(double(state: "open"))
      expect(@worker).to_not receive(:respond_external_template)

      @worker.perform(@locals, { days_before_deadline: 2, reviewer: "@reviewer33"})
    end

    it "should do nothing if due date for the reviewer" do
      expect(@worker).to receive(:issue).and_return(double(state: "open"))
      expect(@worker).to receive(:due_date_for).with("@reviewer33").and_return(nil)
      expect(@worker).to_not receive(:respond_external_template)

      @worker.perform(@locals, @params)
    end

    it "should do nothing if wrong day" do
      five_days_from_now = Date.parse((Time.now + 5*86400).strftime("%Y-%m-%d"))
      expect(@worker).to receive(:issue).and_return(double(state: "open"))
      expect(@worker).to receive(:due_date_for).with("@reviewer33").and_return(five_days_from_now)
      expect(@worker).to_not receive(:respond_external_template)

      @worker.perform(@locals, @params)
    end

    it "should reply reminder using the template" do
      due_date = (Time.now + 2*86400).strftime("%Y-%m-%d")
      issue_test_body = "<!--due-dates-list-->Due date for @reviewer33: #{due_date}<!--end-due-dates-list-->"
      expect(@worker).to receive(:issue).and_return(double(state: "open", body: issue_test_body)).twice

      expected_info =  { reviewer: "@reviewer33", days_before_deadline: 2, due_date: due_date }

      expect(@worker).to receive(:respond_external_template).with("reminder.md", expected_info)
      @worker.perform(@locals, @params)
    end
  end

  describe "due_date_for" do
    before do
      due_dates_list = ["Due date for @Reviewer_A: 11121-invalid-date", "Due date for @Reviewer_B: 2022-06-18"].join("\n")
      expect(@worker).to receive(:read_value_from_body).and_return(due_dates_list)
    end

    it "should be nil if no entry for the reviewer" do
      expect(@worker.due_date_for("@Reviewer_C")).to be_nil
    end

    it "should be nil if invalid due_date for the reviewer" do
      expect(@worker.due_date_for("@Reviewer_A")).to be_nil

    end

    it "should parse the due date for the reviewer" do
      expect(@worker.due_date_for("@Reviewer_B")).to eq(Date.parse("2022-06-18"))
    end
  end
end
