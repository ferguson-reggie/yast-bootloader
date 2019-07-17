require_relative "test_helper"

require "bootloader/autoyast_converter"
require "bootloader/grub2"

Yast.import "Arch"

describe Bootloader::AutoyastConverter do
  subject { described_class }

  describe ".import" do
    before do
      allow(Bootloader::BootloaderFactory).to receive(:proposed).and_return(Bootloader::Grub2.new)
    end

    it "create bootlaoder of passed loader_type" do
      map = {
        "loader_type" => "grub2-efi"
      }

      expect(subject.import(map)).to be_a(Bootloader::Grub2EFI)
    end

    it "use proposed bootloader type if loader type missing" do
      map = {}

      expect(subject.import(map)).to be_a(Bootloader::Grub2)
    end

    it "use proposed bootloader type if loader type is \"default\"" do
      map = {
        "loader_type" => "default"
      }

      expect(subject.import(map)).to be_a(Bootloader::Grub2)
    end

    it "raises exception if loader type is not supported" do
      map = {
        "loader_type" => "lilo"
      }

      expect { subject.import(map) }.to raise_error(Bootloader::UnsupportedBootloader)
    end

    it "import configuration to returned bootloader" do
      data = {
        "append"       => "verbose nomodeset",
        "terminal"     => "gfxterm",
        "os_prober"    => "true",
        "hiddenmenu"   => "true",
        "timeout"      => 10,
        "activate"     => "true",
        "generic_mbr"  => "false",
        "trusted_grub" => "true"
      }

      bootloader = subject.import("global" => data)

      expect(bootloader.grub_default.kernel_params.serialize).to eq "verbose nomodeset"
      expect(bootloader.grub_default.terminal).to eq :gfxterm
      expect(bootloader.grub_default.os_prober).to be_enabled
      expect(bootloader.grub_default.hidden_timeout).to eq "10"
      expect(bootloader.stage1).to be_activate
      expect(bootloader.trusted_boot).to eq true
    end

    it "imports device map for grub2 on intel architecture" do
      allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
      data = {
        "loader_type" => "grub2",
        "device_map"  => [
          { "firmware" => "hd0", "linux" => "/dev/vda" },
          { "firmware" => "hd1", "linux" => "/dev/vdb" }
        ]
      }

      bootloader = subject.import(data)
      expect(bootloader.device_map.system_device_for("hd0")).to eq "/dev/vda"
      expect(bootloader.device_map.system_device_for("hd1")).to eq "/dev/vdb"
    end

    it "supports SLE9 format" do
      data = {
        "activate"      => "true",
        "loader_device" => "/dev/sda1"
      }

      bootloader = subject.import(data)

      expect(bootloader.stage1).to be_activate
      expect(bootloader.stage1).to include("/dev/sda1")
    end
  end

  describe ".export" do
    let(:bootloader) { Bootloader::Grub2.new }
    it "export loader type" do
      expect(subject.export(bootloader)["loader_type"]).to eq "grub2"
    end

    it "export to global key configuration" do
      bootloader.grub_default.kernel_params.replace("verbose nomodeset")
      bootloader.grub_default.terminal = :gfxterm
      bootloader.grub_default.os_prober.enable
      bootloader.grub_default.hidden_timeout = "10"
      bootloader.stage1.activate = true
      bootloader.trusted_boot = true

      expected_export = {
        "append"          => "verbose nomodeset",
        "terminal"        => "gfxterm",
        "os_prober"       => "true",
        "hiddenmenu"      => "true",
        "timeout"         => 10,
        "boot_mbr"        => "false",
        "boot_boot"       => "false",
        "boot_extended"   => "false",
        "boot_root"       => "false",
        "activate"        => "true",
        "generic_mbr"     => "false",
        "trusted_grub"    => "true",
        "cpu_mitigations" => "manual"
      }

      expect(subject.export(bootloader)["global"]).to eq expected_export
    end
  end
end
