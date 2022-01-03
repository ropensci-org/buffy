require_relative "../../spec_helper.rb"

describe Ropensci::ApprovedPackageWorker do

  describe "perform" do
    before do
      @config = {}
      @locals = { issue_author: "user-author"}
      @worker = described_class.new
      disable_github_calls_for(@worker)
    end

    it "should run new_team action" do
      expect(@worker).to receive(:new_team)
      @worker.perform(:new_team, @config, @locals, {})
    end

    it "should run finalize_transfer action" do
      expect(@worker).to receive(:finalize_transfer)
      @worker.perform(:finalize_transfer, @config, @locals, {})
    end
  end

  describe "#new_team" do
    before do
      @worker = described_class.new
      @worker.context = OpenStruct.new({issue_author: "user-author"})
      @worker.params = OpenStruct.new({ team_name: "TestPackage"})
      disable_github_calls_for(@worker)
    end

    it "should invite user to new team" do
      expect(@worker).to receive(:invite_user_to_team).with("user-author", "ropensci/TestPackage" )
      @worker.new_team
    end

    it "should do nothing if empty user to invite" do
      @worker.context = OpenStruct.new({issue_author: nil})
      expect(@worker).to_not receive(:invite_user_to_team)
      @worker.new_team
    end

    it "should do nothing if empty team name" do
      @worker.params = OpenStruct.new({team_name: ""})
      expect(@worker).to_not receive(:invite_user_to_team)
      @worker.new_team
    end
  end

  describe "#finalize_transfer" do
    before do
      @worker = described_class.new
      @worker.context = {}
      @worker.params = OpenStruct.new({ package_name: "test-package", package_author: "test-package_author" })
      disable_github_calls_for(@worker)
      allow(@worker).to receive(:github_access_token).and_return("123ABC")
    end

    it "should check for presence of the transfered repo" do
      allow_any_instance_of(Octokit::Client).to receive(:repository?).with("ropensci/test-package").and_return(false)
      expect(@worker).to receive(:respond).with("Can't find repository `ropensci/test-package`, have you forgotten to transfer it first?")
      @worker.finalize_transfer
    end

    it "should create team and invite author if it doesn't exist" do
      allow_any_instance_of(Octokit::Client).to receive(:repository?).with("ropensci/test-package").and_return(true)
      expect(@worker).to receive(:api_team_id).with("ropensci/test-package").and_return(nil)
      expect(@worker).to receive(:add_new_team).with("ropensci/test-package").and_return(double(id: 1))
      expect(@worker).to receive(:invite_user_to_team).with("test-package_author", "ropensci/test-package")

      expect(Faraday).to receive(:put).and_return(double(status: 200))
      @worker.finalize_transfer
    end

    it "should reply error message if can't create the team" do
      allow_any_instance_of(Octokit::Client).to receive(:repository?).with("ropensci/test-package").and_return(true)
      expect(@worker).to receive(:api_team_id).with("ropensci/test-package").and_return(nil)
      expect(@worker).to receive(:add_new_team).with("ropensci/test-package").and_return(nil)

      expect(@worker).to receive(:respond).with("Could not finalize transfer: Error creating the `ropensci/test-package` team")
      @worker.finalize_transfer
    end

    it "should add repo to team with admin rights" do
      allow_any_instance_of(Octokit::Client).to receive(:repository?).with("ropensci/test-package").and_return(true)
      expect(@worker).to receive(:api_team_id).with("ropensci/test-package").and_return(123)

      expect(Faraday).to receive(:put).and_return(double(status: 200))
      expected_response = "Transfer completed. The `test-package` team is now owner of [the repository](https://github.com/ropensci/test-package)"
      expect(@worker).to receive(:respond).with(expected_response)
      @worker.finalize_transfer
    end

    it "should reply error message if can't add repo to team with admin rights" do
      allow_any_instance_of(Octokit::Client).to receive(:repository?).with("ropensci/test-package").and_return(true)
      expect(@worker).to receive(:api_team_id).with("ropensci/test-package").and_return(123)

      expect(Faraday).to receive(:put).and_return(double(status: 403))
      expected_response = "Could not finalize transfer: Could not add owner rights to the `test-package` team"
      expect(@worker).to receive(:respond).with(expected_response)
      @worker.finalize_transfer
    end
  end
end
