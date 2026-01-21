# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe ZenDownloader::Config do
  describe "#initialize" do
    context "when config file exists with valid credentials" do
      it "loads username and password" do
        config_file = Tempfile.new(["config", ".yml"])
        config_file.write(<<~YAML)
          username: test_user
          password: test_pass
          download_dir: /tmp/downloads
        YAML
        config_file.close

        config = described_class.new(config_file.path)

        expect(config.username).to eq("test_user")
        expect(config.password).to eq("test_pass")
        expect(config.download_dir).to eq("/tmp/downloads")
      ensure
        config_file.unlink
      end
    end

    context "when config file does not exist" do
      it "raises an error" do
        expect {
          described_class.new("/nonexistent/path.yml")
        }.to raise_error(ZenDownloader::Error, /Config file not found/)
      end
    end

    context "when username is missing" do
      it "raises an error" do
        config_file = Tempfile.new(["config", ".yml"])
        config_file.write("password: test_pass\n")
        config_file.close

        expect {
          described_class.new(config_file.path)
        }.to raise_error(ZenDownloader::Error, /username is required/)
      ensure
        config_file.unlink
      end
    end

    context "when password is missing" do
      it "raises an error" do
        config_file = Tempfile.new(["config", ".yml"])
        config_file.write("username: test_user\n")
        config_file.close

        expect {
          described_class.new(config_file.path)
        }.to raise_error(ZenDownloader::Error, /password is required/)
      ensure
        config_file.unlink
      end
    end

    context "when download_dir is not specified" do
      it "defaults to current directory" do
        config_file = Tempfile.new(["config", ".yml"])
        config_file.write(<<~YAML)
          username: test_user
          password: test_pass
        YAML
        config_file.close

        config = described_class.new(config_file.path)

        expect(config.download_dir).to eq(".")
      ensure
        config_file.unlink
      end
    end
  end
end
