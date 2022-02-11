require_relative "../../spec_helper.rb"

describe Ropensci::SetDueDateResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    params = { no_reviewer_text: "TBD" }
    @responder = subject.new(settings, params)
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot set due date for @maelle to 2023-01-21")
      expect(@responder.event_regex).to match("@ropensci-review-bot set due date for @maelle to: 2024-11-17")
      expect(@responder.event_regex).to match("@ropensci-review-bot set due date for @maelle to: 2024-11-17  \r\n")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot set due date for @maelle")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot set due date for @maelle: tomorrow")
    end
  end

  describe "#process_message" do
    before do
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 32,
                                          issue_author: "opener",
                                          repo: "openjournals/testing",
                                          sender: "xuanxu")
    end

    describe "setting new due date" do
      before do
        @new_due_date = Date.today + 15
        @new_date_string = @new_due_date.strftime("%Y-%m-%d")
        @msg = "@ropensci-review-bot set due date for @maelle to #{@new_date_string}"
        @responder.match_data = @responder.event_regex.match(@msg)
        issue_body = "...Reviewers: <!--reviewers-list-->@reviewer1, @maelle<!--end-reviewers-list-->" +
                     "<!--due-dates-list-->Due date for @reviewer1: 2121-12-31\nDue date for @maelle: 2100-12-31<!--end-due-dates-list--> ..."
        allow(@responder).to receive(:issue_body).and_return(issue_body)
      end

      it "should update due dates list" do
        expected_new_due_dates_list = "Due date for @reviewer1: 2121-12-31\nDue date for @maelle: #{@new_date_string}"
        expect(@responder).to receive(:update_list).with("due-dates", expected_new_due_dates_list)
        @responder.process_message(@msg)
      end

      it "due add due date if not present" do
        issue_body = "...Reviewers: <!--reviewers-list-->@reviewer1, @maelle<!--end-reviewers-list-->" +
                     "<!--due-dates-list-->Due date for @reviewer1: 2121-12-31<!--end-due-dates-list--> ..."
        allow(@responder).to receive(:issue_body).and_return(issue_body)

        expected_new_due_dates_list = "Due date for @reviewer1: 2121-12-31\nDue date for @maelle: #{@new_date_string}"
        expect(@responder).to receive(:update_list).with("due-dates", expected_new_due_dates_list)
        expect(@responder).to receive(:respond).with("Review due date for @maelle is now #{@new_due_date.strftime('%d-%B-%Y')}")
        @responder.process_message(@msg)
      end

      it "should respond to github" do
        expect(@responder).to receive(:respond).with("Review due date for @maelle is now #{@new_due_date.strftime('%d-%B-%Y')}")
        @responder.process_message(@msg)
      end

      it "should not work if due date has wrong format" do
        msg = "@ropensci-review-bot set due date for @maelle to 2123/21/05"
        @responder.match_data = @responder.event_regex.match(msg)
        expect(@responder).to_not receive(:update_list)
        expect(@responder).to receive(:respond).with("Wrong due date format, please use: `YYYY-MM-DD`")
        @responder.process_message(msg)
      end

      it "should work only for current reviewers" do
        msg = "@ropensci-review-bot set due date for @reviewer3 to: #{@new_date_string}"
        @responder.match_data = @responder.event_regex.match(msg)
        expect(@responder).to_not receive(:update_list)
        expect(@responder).to receive(:respond).with("Can't set due date: @reviewer3 is not included in the reviewers list")
        @responder.process_message(msg)
      end

      it "should not accept past due dates" do
        yesterday = Date.today - 1
        msg = "@ropensci-review-bot set due date for @maelle to #{yesterday.strftime("%Y-%m-%d")}"
        @responder.match_data = @responder.event_regex.match(msg)
        expect(@responder).to_not receive(:update_list)
        expect(@responder).to receive(:respond).with("Can't set due date: #{yesterday.strftime('%d/%B/%Y')} is in the past")
        @responder.process_message(msg)
      end
    end
  end
end