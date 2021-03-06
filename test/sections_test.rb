#! /usr/bin/env rspec --format doc
# frozen_string_literal: true

require_relative "./test_helper"

require "bootloader/sections"
require "cfa/memory_file"

describe Bootloader::Sections do
  subject do
    sections = [
      { title: "linux", path: "linux" },
      { title: "windows", path: "alien>windows" }
    ]
    grub_cfg = double("CFA::Grub2::GrubCfg", boot_entries: sections)
    Bootloader::Sections.new(grub_cfg)
  end

  describe "#all" do
    it "returns list of all available sections" do
      expect(subject.all).to eq(["linux", "windows"])
    end
  end

  describe "#default" do
    it "gets name of default section stored in grub2" do
      expect(Yast::Execute).to receive(:on_target)
        .with("/usr/bin/grub2-editenv", "list", stdout: :capture)
        .and_return("saved_entry=alien>windows\nbla_bla=no\n")

      expect(subject.default).to eq "windows"
    end

    it "gets first section if nothing stored in grub2" do
      expect(Yast::Execute).to receive(:on_target)
        .with("/usr/bin/grub2-editenv", "list", stdout: :capture)
        .and_return("\n")

      expect(subject.default).to eq "linux"
    end

    it "gets value written by #default=" do
      subject.default = "windows"

      expect(subject.default).to eq "windows"
    end
  end

  describe "#default=" do
    it "sets new value for default" do
      subject.default = "windows"

      expect(subject.default).to eq "windows"
    end

    it "sets default to empty if section do not exists" do
      subject.default = "non-exist"
      expect(subject.default).to eq ""
    end

    it "handles localized grub.cfg" do
      data_path = File.expand_path("data/grub.cfg", __dir__)
      file = CFA::MemoryFile.new(File.read(data_path))
      grub_cfg = CFA::Grub2::GrubCfg.new(file_handler: file)
      grub_cfg.load

      sections = Bootloader::Sections.new(grub_cfg)

      expect { sections.default = "openSUSE Tumbleweed, с Linux 4.8.6-2-default" }.to_not raise_error
      expect { sections.default = "openSUSE Tumbleweed, \u0441 Linux 4.8.6-2-default" }.to_not raise_error
      expect { sections.default = "openSUSE Tumbleweed, \xD1\x81 Linux 4.8.6-2-default" }.to_not raise_error
    end
  end

  describe "#write" do
    it "writes default value" do
      subject.default = "linux"

      expect(Yast::Execute).to receive(:on_target)
        .with("/usr/sbin/grub2-set-default", "linux")

      subject.write
    end

    it "converts default value to its path" do
      subject.default = "windows"

      expect(Yast::Execute).to receive(:on_target)
        .with("/usr/sbin/grub2-set-default", "alien>windows")

      subject.write
    end
  end
end
