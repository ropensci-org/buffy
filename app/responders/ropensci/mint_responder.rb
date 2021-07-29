require_relative '../../lib/responder'

module Ropensci
  class MintResponder < Responder

    keyname :ropensci_mint

    VALID_METAL_VALUES = %w(bronze silver gold)
    VALID_SUBMISSION_TYPES = %w(stats)

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} mint( [ \w-]+)?\.?\s*\z/i
    end

    def process_message(message)
      if valid_metal? && valid_submission_type?
          update_or_add_value("statsgrade", @metal, append: false, heading: "Badge grade")
          respond("Done, #{@metal} minted!")
          process_labeling
      else
        respond(@error_reply)
      end
    end

    def valid_metal?
      @error_reply = "Couldn't mint. Please provide a valid value (#{VALID_METAL_VALUES.join('/')})."
      @metal = @match_data[1].to_s.strip.downcase
      VALID_METAL_VALUES.include?(@metal)
    end

    def valid_submission_type?
      @error_reply = "Only submissions type: #{VALID_SUBMISSION_TYPES.join('/')} can be minted"
      submission_type = read_value_from_body("submission-type").downcase
      VALID_SUBMISSION_TYPES.include?(submission_type)
    end

    def description
      "Mint package as [#{VALID_METAL_VALUES.join("/")}]"
    end

    def example_invocation
      "@#{bot_name} mint silver"
    end
  end
end
