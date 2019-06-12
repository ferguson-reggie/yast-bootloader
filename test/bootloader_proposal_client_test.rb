# typed: false
require_relative "test_helper"

require "bootloader/proposal_client"

require "bootloader/bootloader_factory"
require "bootloader/main_dialog"

Yast.import "Mode"

describe Bootloader::ProposalClient do
  before do
    Bootloader::BootloaderFactory.clear_cache

    allow(Yast::Bootloader).to receive(:Reset)
  end

  describe "#description" do
    it "returns map with rich_text_title, menu_title and id" do
      result = subject.description

      expect(result.keys.sort).to eq ["id", "menu_title", "rich_text_title"]
    end
  end

  describe "#ask_user" do
    let(:stage1) { ::Bootloader::BootloaderFactory.current.stage1 }
    context "single click action is passed" do
      before do
        Yast.import "Bootloader"

        ::Bootloader::BootloaderFactory.current_name = "grub2"
      end

      it "if id contain enable it enabled respective key" do
        subject.ask_user("chosen_id" => "enable_boot_mbr")

        expect(stage1.mbr?).to eq true
      end

      it "if id contain disable it disabled respective key" do
        subject.ask_user("chosen_id" => "disable_boot_mbr")

        expect(stage1.mbr?).to eq false
      end

      it "it returns \"workflow sequence\" with :next" do
        expect(subject.ask_user("chosen_id" => "disable_boot_mbr")).to(
          eq("workflow_sequence" => :next)
        )
      end

      it "sets to true that proposed cfg changed" do
        subject.ask_user("chosen_id" => "disable_boot_boot")

        expect(Yast::Bootloader.proposed_cfg_changed).to be true
      end
    end

    context "gui id is passed" do
      before do
        Yast.import "Bootloader"

        allow(Yast::Bootloader).to receive(:Export).and_return({})
        Yast::Bootloader.proposed_cfg_changed = false
      end

      it "returns as workflow sequence result of GUI" do
        allow_any_instance_of(::Bootloader::MainDialog).to receive(:run_auto).and_return(:next)

        expect(subject.ask_user({})).to eq("workflow_sequence" => :next)
      end

      it "sets to true that poposed cfg changed if GUI changes are confirmed" do
        allow_any_instance_of(::Bootloader::MainDialog).to receive(:run_auto).and_return(:next)

        subject.ask_user({})

        expect(Yast::Bootloader.proposed_cfg_changed).to be true
      end

      it "restores previous configuration if GUI is canceled" do
        allow_any_instance_of(::Bootloader::MainDialog).to receive(:run_auto).and_return(:cancel)
        expect(Yast::Bootloader).to receive(:Import).with({})

        subject.ask_user({})
      end
    end
  end

  describe "#make_proposal" do
    before do
      ::Bootloader::BootloaderFactory.current_name = "grub2"
      allow(Yast::Bootloader).to receive(:Propose)
      allow(Yast::Bootloader).to receive(:Summary).and_return("Summary")
      allow(Yast::BootStorage).to receive(:bootloader_installable?).and_return(true)

      Yast.import "Arch"
      allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
    end

    it "returns map with links set to single click actions" do
      expect(subject.make_proposal({})).to include("links")
    end

    it "returns map with raw_proposal set to respective bootloader summary" do
      expect(Yast::Bootloader).to receive(:Summary).and_return("Summary")

      expect(subject.make_proposal({})).to include("raw_proposal")
    end

    it "proposes a none bootloader if the boot filesystem is nfs" do
      devicegraph_stub("nfs_root.xml")
      subject.make_proposal({})
      expect(Yast::BootStorage.boot_filesystem.is?(:nfs)).to eq(true)
      expect(::Bootloader::BootloaderFactory.current.name).to eq("none")
    end

    it "report warning if no bootloader selected" do
      ::Bootloader::BootloaderFactory.current_name = "none"

      result = subject.make_proposal({})

      expect(result["warning_level"]).to eq :warning
      expect(result["warning"]).to_not be_empty
    end

    it "report error if bootloader is not installable" do
      expect(Yast::BootStorage).to receive(:bootloader_installable?).and_return(false)

      result = subject.make_proposal({})

      expect(result["warning_level"]).to eq :error
      expect(result["warning"]).to_not be_empty
    end

    it "reports error if system setup is not supported" do
      Yast.import "BootSupportCheck"
      expect(Yast::BootSupportCheck).to receive(:SystemSupported).and_return(false)
      expect(Yast::BootSupportCheck).to receive(:StringProblems).and_return("We have problem!")

      result = subject.make_proposal({})

      expect(result["warning_level"]).to eq :error
      expect(result["warning"]).to_not be_empty
    end

    it "call bootloader propose in common installation" do
      allow(Yast::Mode).to receive(:update).and_return(false)
      expect(Bootloader::BootloaderFactory.current).to receive(:propose)

      subject.make_proposal({})
    end

    it "reproprose from scrach during update if old bootloader is not grub2" do
      allow(Yast::Mode).to receive(:update).and_return(true)

      expect(subject).to receive("old_bootloader").and_return("grub").at_least(:once)

      expect(Yast::Bootloader).to receive(:Reset).at_least(:once)
      expect(Bootloader::BootloaderFactory).to receive(:proposed).and_call_original

      subject.make_proposal({})
    end

    it "do not propose during update if if old bootloader is none" do
      allow(Yast::Mode).to receive(:update).and_return(true)

      expect(subject).to receive("old_bootloader").and_return("none").twice

      subject.make_proposal({})
    end

    it "always resets if storage changed" do
      expect(Yast::Bootloader).to receive(:Reset)
      allow(Yast::BootStorage).to receive(:storage_changed?).and_return(true)

      subject.make_proposal("force_reset" => true)
    end

    it "resets configuration if not automode and force_reset passed" do
      expect(Yast::Bootloader).to receive(:Reset)

      subject.make_proposal("force_reset" => true)
    end

    it "do not resets configuration in automode and even if force_reset passed" do
      allow(Yast::Mode).to receive(:autoinst).and_return(true)
      expect(Yast::Bootloader).to_not receive(:Reset)

      subject.make_proposal("force_reset" => true)
    end

    it "updates resolvables with necessary packages" do
      current_packages = Yast::PackagesProposal.GetResolvables("yast2-bootloader", :package)
      packages_to_propose = ::Bootloader::BootloaderFactory.current.packages
      expect(Yast::PackagesProposal).to receive(:RemoveResolvables).with("yast2-bootloader", :package, current_packages)
      expect(Yast::PackagesProposal).to receive(:AddResolvables).with("yast2-bootloader", :package, packages_to_propose)
      subject.make_proposal({})
    end

    it "returns warning if old system use different boot technology then new one" do
      allow(Yast::Mode).to receive(:update).and_return(true)

      expect(subject).to receive("old_bootloader").and_return("grub2-efi").at_least(:once)

      expect(subject.make_proposal({})["warning_level"]).to eq :warning
    end
  end
end
