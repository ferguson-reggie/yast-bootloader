require "installation/proposal_client"
require "bootloader/exceptions"
require "bootloader/main_dialog"
require "bootloader/bootloader_factory"

module Bootloader
  # Proposal client for bootloader configuration
  class ProposalClient < ::Installation::ProposalClient
    include Yast::I18n
    include Yast::Logger

    def initialize
      Yast.import "UI"
      textdomain "bootloader"

      Yast.import "Arch"
      Yast.import "BootStorage"
      Yast.import "Bootloader"
      Yast.import "Installation"
      Yast.import "Storage"
      Yast.import "Mode"
      Yast.import "BootSupportCheck"
      Yast.import "Product"
      Yast.import "PackagesProposal"
    end

    PROPOSAL_LINKS = [
      "enable_boot_mbr",
      "disable_boot_mbr",
      "enable_boot_root",
      "disable_boot_root",
      "enable_boot_boot",
      "disable_boot_boot"
    ].freeze

    def make_proposal(attrs)
      force_reset = attrs["force_reset"]
      storage_changed = Yast::BootStorage.storage_changed?
      storage_read = Yast::BootStorage.storage_read?
      # redetect disks if cache is invalid as first part
      Yast::BootStorage.detect_disks if storage_changed
      log.info "Storage changed: #{storage_changed} force_reset #{force_reset}."
      log.info "Storage read previously #{storage_read.inspect}"

      if reset_needed?(force_reset, storage_changed && storage_read)
        # force re-calculation of bootloader proposal
        # this deletes any internally cached values, a new proposal will
        # not be partially based on old data now any more
        log.info "Recalculation of bootloader configuration"
        Yast::Bootloader.Reset
      end

      if Yast::Mode.update
        return { "raw_proposal" => [_("do not change")] } unless propose_for_update(force_reset)
      elsif Yast::Bootloader.proposed_cfg_changed
        # do nothing as user already modify it
      else
        # in installation always propose missing stuff
        # current below use proposed value if not already set
        # If set, then use same bootloader, but propose it again
        bl = ::Bootloader::BootloaderFactory.current
        bl.propose
      end

      bl = ::Bootloader::BootloaderFactory.current
      log.info "propose to install #{bl.packages}"
      Yast::PackagesProposal.AddResolvables("yast2-bootloader", :package, bl.packages)

      construct_proposal_map
    rescue ::Bootloader::NoRoot
      {
        "label_proposal" => [],
        "warning_level"  => :fatal,
        "warning"        => _("Cannot detect device mounted as root. Please check partitioning.")
      }
    end

    def ask_user(param)
      chosen_id = param["chosen_id"]
      result = :next
      log.info "ask user called with #{chosen_id}"

      # enable boot from MBR
      case chosen_id
      when *PROPOSAL_LINKS
        value = chosen_id =~ /enable/ ? true : false
        option = chosen_id[/(enable|disable)_boot_(.*)/, 2]
        single_click_action(option, value)
      else
        settings = Yast::Bootloader.Export
        result = ::Bootloader::MainDialog.new.run_auto
        if result != :next
          Yast::Bootloader.Import(settings)
        else
          Yast::Bootloader.proposed_cfg_changed = true
        end
      end
      # Fill return map
      { "workflow_sequence" => result }
    end

    def description
      {
        # proposal part - bootloader label
        "rich_text_title" => _("Booting"),
        # menubutton entry
        "menu_title"      => _("&Booting"),
        "id"              => "bootloader_stuff"
      }
    end

  private

    # returns if proposal should be reseted
    # logic in this condition:
    # when reset is forced or user do not modify proposal, reset proposal,
    # but only when not using auto_mode
    # But if storage changed, always repropose as it can be very wrong.
    def reset_needed?(force_reset, storage_changed)
      return true if storage_changed
      return false if Yast::Mode.autoinst || Yast::Mode.autoupgrade
      force_reset || !Yast::Bootloader.proposed_cfg_changed
    end

    BOOT_SYSCONFIG_PATH = "/etc/sysconfig/bootloader".freeze
    # read bootloader from /mnt as SCR is not yet switched in proposal
    # phase of update (bnc#874646)
    def old_bootloader
      target_boot_sysconfig_path = ::File.join(Yast::Installation.destdir, BOOT_SYSCONFIG_PATH)
      return nil unless ::File.exist? target_boot_sysconfig_path

      boot_sysconfig = ::File.read target_boot_sysconfig_path
      old_bootloader = boot_sysconfig.lines.grep(/^\s*LOADER_TYPE/)
      log.info "bootloader entry #{old_bootloader.inspect}"
      return nil if old_bootloader.empty?

      # get value from entry
      old_bootloader.last.chomp.sub(/^.*=\s*(\S*).*/, "\\1").delete('"\'')
    end

    def propose_for_update(force_reset)
      current_bl = ::Bootloader::BootloaderFactory.current
      log.info "update detection:"
      log.info "proposed? #{current_bl.proposed?}"
      log.info "config changed? #{Yast::Bootloader.proposed_cfg_changed}"

      if ["grub2", "grub2-efi"].include?(old_bootloader) &&
          !current_bl.proposed? &&
          !Yast::Bootloader.proposed_cfg_changed
        log.info "update of grub2, do not repropose"
        return false
      elsif old_bootloader == "none"
        log.info "Bootloader not configured, do not repropose"
        # blRead just exits for none bootloader
        ::Bootloader::BootloaderFactory.current_name = "none"
        ::Bootloader::BootloaderFactory.current.read

        return false
      elsif !current_bl.proposed? || force_reset
        # Repropose the type. A regular Reset/Propose is not enough.
        # For more details see bnc#872081
        Yast::Bootloader.Reset
        ::Bootloader::BootloaderFactory.clear_cache
        proposed = ::Bootloader::BootloaderFactory.proposed
        proposed.propose
        ::Bootloader::BootloaderFactory.current = proposed
      end

      current_bl = ::Bootloader::BootloaderFactory.current

      log.info "propose to install #{current_bl.packages}"
      Yast::PackagesProposal.AddResolvables("yast2-bootloader", :package, current_bl.packages)

      true
    end

    def construct_proposal_map
      ret = {}

      ret["links"] = PROPOSAL_LINKS # use always possible links even if it maybe not used
      ret["raw_proposal"] = Yast::Bootloader.Summary
      ret["label_proposal"] = Yast::Bootloader.Summary(simple_mode: true)

      # F#300779 - Install diskless client (NFS-root)
      # kokso:  bootloader will not be installed
      device = Yast::BootStorage.disk_with_boot_partition
      log.info "Type of BootPartitionDevice: #{device}"
      if device == "/dev/nfs"
        log.info "Boot partition is nfs type, bootloader will not be installed."
        return ret
      end
      # F#300779 - end

      handle_errors(ret)

      ret
    end

    # Add to argument proposal map all errors detected by proposal
    # @return modified parameter
    def handle_errors(ret)
      if ::Bootloader::BootloaderFactory.current.name == "none"
        log.error "No bootloader selected"
        ret["warning_level"] = :warning
        # warning text in the summary richtext
        ret["warning"] = _(
          "No boot loader is selected for installation. Your system might not be bootable."
        )
      end

      if !Yast::BootStorage.bootloader_installable?
        ret["warning_level"] = :error
        ret["warning"] = _(
          "Because of the partitioning, the bootloader cannot be installed properly"
        )
      end

      if !Yast::BootSupportCheck.SystemSupported
        ret["warning_level"] = :error
        ret["warning"] = Yast::BootSupportCheck.StringProblems
      end

      ret
    end

    def single_click_action(option, value)
      stage1 = ::Bootloader::BootloaderFactory.current.stage1
      locations = stage1.available_locations
      device = locations[option.to_sym] or raise "invalid option #{option}"
      log.info "single_click_action #{option} #{value.inspect} #{device}"

      value ? stage1.add_udev_device(device) : stage1.remove_device(device)

      Yast::Bootloader.proposed_cfg_changed = true
    end
  end
end
