using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;

namespace MacCleaner.Win.Core.Performance;

public sealed record BluetoothDeviceRow(
    string Id,
    string Name,
    bool IsConnected,
    bool IsPaired,
    bool IsLowEnergy);

public interface IBluetoothService
{
    Task<IReadOnlyList<BluetoothDeviceRow>> ListAsync(CancellationToken ct = default);
}

/// <summary>
/// Enumerates paired Bluetooth devices via WinRT DeviceInformation.
/// Both classic BR/EDR and BLE are surfaced through their respective
/// AQS selectors so the list reads consistently regardless of radio type.
/// </summary>
public sealed class BluetoothService : IBluetoothService
{
    public async Task<IReadOnlyList<BluetoothDeviceRow>> ListAsync(CancellationToken ct = default)
    {
        var rows = new List<BluetoothDeviceRow>();

        // Classic Bluetooth devices (BR/EDR — headsets, keyboards, etc.)
        var classicSelector = BluetoothDevice.GetDeviceSelectorFromPairingState(true);
        var classic = await DeviceInformation.FindAllAsync(classicSelector).AsTask(ct);
        foreach (var d in classic)
        {
            rows.Add(new BluetoothDeviceRow(
                Id: d.Id,
                Name: string.IsNullOrEmpty(d.Name) ? "Unknown" : d.Name,
                IsConnected: d.Properties.TryGetValue("System.Devices.Connected", out var c) && c is bool b && b,
                IsPaired: d.Pairing.IsPaired,
                IsLowEnergy: false));
        }

        // Bluetooth LE devices
        var leSelector = BluetoothLEDevice.GetDeviceSelectorFromPairingState(true);
        var le = await DeviceInformation.FindAllAsync(leSelector).AsTask(ct);
        foreach (var d in le)
        {
            rows.Add(new BluetoothDeviceRow(
                Id: d.Id,
                Name: string.IsNullOrEmpty(d.Name) ? "Unknown LE" : d.Name,
                IsConnected: d.Properties.TryGetValue("System.Devices.Connected", out var c) && c is bool b && b,
                IsPaired: d.Pairing.IsPaired,
                IsLowEnergy: true));
        }

        return rows;
    }
}
