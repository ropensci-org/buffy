require_relative "../../spec_helper.rb"

describe Ropensci::MintResponder do

  subject do
    described_class
  end

  before do
    settings = { env: {bot_github_user: "ropensci-review-bot"} }
    params = {}
    @responder = subject.new(settings, params)
  end

  describe "listening" do
    it "should listen to new comments" do
      expect(@responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex" do
      expect(@responder.event_regex).to match("@ropensci-review-bot mint gold")
      expect(@responder.event_regex).to match("@ropensci-review-bot mint   silver")
      expect(@responder.event_regex).to match("@ropensci-review-bot mint\r\n")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot mintgold")
      expect(@responder.event_regex).to_not match("@wrong-bot mint gold")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot mint gold. another-command")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot mint gold\r\nanother-command")
    end
  end

  describe "#process_message" do
    before do
      @issue_body = "... <!--submission-type-->stats<!--end-submission-type--> ..."
      @msg = "@ropensci-review-bot mint gold"
      @metal_error_response = "Couldn't mint. Please provide a valid value (#{subject::VALID_METAL_VALUES.join("/")})."
      @submission_type_error_response = "Only submissions type: #{subject::VALID_SUBMISSION_TYPES.join('/')} can be minted"
      disable_github_calls_for(@responder)
    end

    it "should verify metal is present" do
      msg = "@ropensci-review-bot mint"
      @responder.match_data = @responder.event_regex.match(msg)

      expect(@responder).to receive(:respond).with(@metal_error_response)

      @responder.process_message(msg)
    end

    it "should verify metal is valid" do
      msg = "@ropensci-review-bot mint lead"
      @responder.match_data = @responder.event_regex.match(msg)

      expect(@responder).to receive(:respond).with(@metal_error_response)

      @responder.process_message(msg)
    end

    it "should verify submission-type is present" do
      issue_body = "...  ..."
      allow(@responder).to receive(:issue_body).and_return(issue_body)
      msg = "@ropensci-review-bot mint gold"
      @responder.match_data = @responder.event_regex.match(msg)

      expect(@responder).to receive(:respond).with(@submission_type_error_response)

      @responder.process_message(msg)
    end

    it "should verify submission-type is valid" do
      issue_body = "... <!--submission-type-->standard<!--end-submission-type--> ..."
      allow(@responder).to receive(:issue_body).and_return(issue_body)
      msg = "@ropensci-review-bot mint gold"
      @responder.match_data = @responder.event_regex.match(msg)

      expect(@responder).to receive(:respond).with(@submission_type_error_response)

      @responder.process_message(msg)
    end

    it "should add statsgrade" do
      @responder.match_data = @responder.event_regex.match(@msg)
      allow(@responder).to receive(:issue_body).and_return(@issue_body)

      expect(@responder).to receive(:update_or_add_value).with("statsgrade", "gold", append: false, heading: "Badge grade")

      @responder.process_message(@msg)
    end

    it "should reply ok message" do
      @responder.match_data = @responder.event_regex.match(@msg)
      allow(@responder).to receive(:issue_body).and_return(@issue_body)

      expect(@responder).to receive(:respond).with("Done, gold minted!")

      @responder.process_message(@msg)
    end

    it "should process labeling" do
      @responder.match_data = @responder.event_regex.match(@msg)
      allow(@responder).to receive(:issue_body).and_return(@issue_body)

      expect(@responder).to receive(:process_labeling)

      @responder.process_message(@msg)
    end
  end
end
