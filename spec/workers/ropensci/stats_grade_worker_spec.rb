require_relative "../../spec_helper.rb"

describe Ropensci::StatsGradesWorker do

  describe "perform" do
    before do
      @locals = { issue_id: 12, repo: "ropensci/tests"}
      @worker = described_class.new
      disable_github_calls_for(@worker)
    end

    it "should run label action" do
      expect(@worker).to receive(:label)
      @worker.perform(:label, @locals, {})
    end
  end

  describe "#label" do
    before do
      @worker = described_class.new
      @worker.context = OpenStruct.new({ issue_id: 12, repo: "ropensci/tests"})
      @worker.params = OpenStruct.new({})
      disable_github_calls_for(@worker)

      @response_ok = OpenStruct.new(status: 200, body: "Approved-gold-v0.0.1".to_json)
    end

    it "should call default external service to get label" do
      expected_url = "http://138.68.123.59:8000/stats_badge"
      expected_parameters = { repo: "ropensci/tests", issue_num: 12}
      expect(Faraday).to receive(:get).with(expected_url, expected_parameters, {}).and_return(@response_ok)

      @worker.label
    end

    it "should call custom external service to get label" do
      expected_url = "http://test.ropensci:8000/stats_labels"
      @worker.params[:stats_badge_url] = expected_url
      expected_parameters = { repo: "ropensci/tests", issue_num: 12}
      expect(Faraday).to receive(:get).with(expected_url, expected_parameters, {}).and_return(@response_ok)

      @worker.label
    end

    it "should label issue with received label" do
      expect(Faraday).to receive(:get).and_return(@response_ok)
      expect(@worker).to receive(:label_issue).with(["Approved-gold-v0.0.1"])

      @worker.label
    end

    it "should log an error if external call fails" do
      expected_error_msg = "Error: The stats badge service failed with response 500 (called https://tests.test for ropensci/tests issue 12)"
      @worker.params[:stats_badge_url] = "https://tests.test"
      expect(Faraday).to receive(:get).and_return(OpenStruct.new(status: 500))
      #expect(@worker.logger).to receive(:warn).with(expected_error_msg)

      @worker.label
    end
  end
end
