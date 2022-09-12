# frozen_string_literal: true

require "spec_helper"

describe ForemanEnvsync do
  describe "#verbose_list" do
    before { @options = { verbose: true } }

    context "with array of hash" do
      let(:aofh) { [{ a: 1 }, { b: 2 }] }
      let(:foo_output) do
        <<~FOO
          foo
          ---
          - :a: 1
          - :b: 2

        FOO
      end

      it { expect { verbose_list("foo", aofh) }.to output(foo_output).to_stdout }
    end
  end
end
