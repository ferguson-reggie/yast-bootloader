# typed: false
require_relative "test_helper"

require "bootloader/device_map_dialog"

describe Bootloader::DeviceMapDialog do
  let(:device_map) do
    device_map = Bootloader::DeviceMap.new
    device_map.add_mapping("hd0", "/dev/sda")
    device_map.add_mapping("hd1", "/dev/sdb")

    device_map
  end

  subject { Bootloader::DeviceMapDialog.new(device_map) }

  # just simple tests to avoid typos as logic is not so easy to test
  describe "#run" do
    before do
      allow(Yast::UI).to receive(:QueryWidget).and_return("/dev/sda")
      allow(Yast::UI).to receive(:OpenDialog).and_return(true)
      allow(Yast::UI).to receive(:CloseDialog).and_return(true)
    end

    def mock_ui_events(*events)
      allow(Yast::UI).to receive(:UserInput).and_return(*events)
    end

    it "always returns symbol :back" do
      mock_ui_events(:ok)

      expect(subject.run).to eq :back

      mock_ui_events(:cancel)

      expect(subject.run).to eq :back
    end

    it "allows adding disks after clicking on button" do
      # need additional ok for adding dialog
      mock_ui_events(:add, :ok, :ok)
      allow(Yast::UI).to receive(:QueryWidget).with(anything, :SelectedItems)
        .and_return(["/dev/sda", "/dev/sda", "/dev/sdb"])

      expect(subject.run).to eq :back
    end

    it "allows adding disks in config mode after clicking on button" do
      # need additional ok for adding dialog
      mock_ui_events(:add, :ok, :ok)
      allow(Yast::Mode).to receive(:config).and_return(true)

      expect(subject.run).to eq :back
    end

    it "allows adding disks in auto mode after clicking on button" do
      # need additional ok for adding dialog
      mock_ui_events(:add, :ok, :ok)
      allow(Yast::Mode).to receive(:auto).and_return(true)

      expect(subject.run).to eq :back
    end

    it "allows removing disks after clicking on button" do
      mock_ui_events(:delete, :ok)
      # need to simulate that disk gone
      allow(Yast::UI).to receive(:QueryWidget).and_return("/dev/sda", "/dev/sda", "/dev/sdb")

      expect(subject.run).to eq :back
    end

    it "allows moving disk in order up by clicking on button" do
      mock_ui_events(:up, :ok)

      expect(subject.run).to eq :back
    end

    it "allows moving disk in order down by clicking on button" do
      mock_ui_events(:down, :ok)

      expect(subject.run).to eq :back
    end

    it "react when user change selection in disk order" do
      mock_ui_events(:disks, :ok)

      expect(subject.run).to eq :back
    end
  end
end
