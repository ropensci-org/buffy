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
end
