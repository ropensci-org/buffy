require_relative "../../spec_helper.rb"

describe Ropensci::InvitePackageAuthorResponder do

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
      expect(@responder.event_regex).to match("@ropensci-review-bot invite me to ropensci/package-name")
      expect(@responder.event_regex).to match("@ropensci-review-bot invite me to package-name")
      expect(@responder.event_regex).to match("@ropensci-review-bot invite me to package-name  \r\n")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot finvite me to package-name. another-command")
      expect(@responder.event_regex).to_not match("@ropensci-review-bot finvite me to package-name\r\nanother-command")
    end
  end

  describe "#process_message" do
    before do
      @msg = "@ropensci-review-bot invite me to ropensci/great-package"
      @responder.match_data = @responder.event_regex.match(@msg)
      disable_github_calls_for(@responder)
      @responder.context = OpenStruct.new(issue_id: 33,
                                          issue_author: "author",
                                          repo: "openjournals/testing-approval",
                                          sender: "author")
    end

    it "should verify presence of package name" do
      msg = "@ropensci-review-bot invite me to "
      @responder.match_data = @responder.event_regex.match(msg)
      expect(@responder).to receive(:respond).with("Could not invite: Please, specify the name of the team (should match the name of the package at the rOpenSci org)")
      @responder.process_message(msg)
    end

    it "should verify presence of package author" do
      msg = "@ropensci-review-bot invite me to nice-package"
      @responder.match_data = @responder.event_regex.match(msg)
      @responder.context[:issue_author] = nil
      expect(@responder).to receive(:respond).with("Could not invite, you are not the author of the package")
      @responder.process_message(msg)
    end

    it "should verify command sender is the author" do
      msg = "@ropensci-review-bot invite me to nice-package"
      @responder.match_data = @responder.event_regex.match(msg)
      @responder.context[:issue_author] = "another-user"
      expect(@responder).to receive(:respond).with("Could not invite, you are not the author of the package")
      @responder.process_message(msg)
    end

    it "should create a job to send the invitation" do
      expect(Ropensci::ApprovedPackageWorker).to receive(:perform_async).
                                                 with(:invite_author_to_transfered_repo,
                                                      @responder.params,
                                                      @responder.locals,
                                                      {package_author: "author", package_name: "ropensci/great-package"})

      @responder.process_message(@msg)
    end
  end
end
