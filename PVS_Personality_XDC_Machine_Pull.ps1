# Function to check if it's a Citrix PVS Server (using StreamService as an indicator)
function Is-PVSServer {
    try {
        # Check if the StreamService is running (PVS-related service)
        $pvsService = Get-Service -Name "StreamService" -ErrorAction SilentlyContinue
        if ($pvsService -and $pvsService.Status -eq 'Running') {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

# Function to check if it's a Citrix Delivery Controller
function Is-DeliveryController {
    try {
        # Check if Citrix Broker Service is running (specific to Delivery Controllers)
        $brokerService = Get-Service -Name "Citrix Broker Service" -ErrorAction SilentlyContinue
        if ($brokerService -and $brokerService.Status -eq 'Running') {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

# Main logic based on the server type
if (Is-PVSServer) {
    # If it's a PVS server, run the PVS-related script
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName "System.Windows.Forms"  # Load the necessary assembly for the SaveFileDialog

    [xml]$XAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="PVS Device Personality Retrieval" Height="400" Width="650"
        WindowStartupLocation="CenterScreen">
    <Grid>
        <TextBlock Text="Select Details to Retrieve:" FontSize="14" Margin="10,10,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
        
        <CheckBox Name="chkDevices" Content="List of Devices" IsChecked="True" Margin="10,40,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkReboot" Content="Reboot Day" Margin="10,70,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkCSR" Content="CSR Server" Margin="10,100,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkXDC" Content="XDC Server" Margin="10,130,0,0" VerticalAlignment="Top"/>
        
        <ProgressBar Name="progressBar" Height="20" Width="600" Margin="10,210,0,0" VerticalAlignment="Top" Visibility="Hidden"/>
        
        <DataGrid Name="dataGrid" Margin="10,240,10,60" AutoGenerateColumns="True"/>

        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="10,170,10,10" VerticalAlignment="Top">
            <Button Name="btnRetrieve" Content="Retrieve Data" Width="150" Height="30" Margin="10,0" VerticalAlignment="Top"/>
            <Button Name="btnExport" Content="Export to CSV" Width="150" Height="30" Margin="10,0" VerticalAlignment="Top"/>
            <Button Name="btnClose" Content="Close" Width="100" Height="30" Margin="10,0"/>
        </StackPanel>

    </Grid>
</Window>
"@

    # Load XAML and bind controls
    $reader = (New-Object System.Xml.XmlNodeReader $XAML)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Access UI Elements
    $chkDevices = $window.FindName("chkDevices")
    $chkReboot = $window.FindName("chkReboot")
    $chkCSR = $window.FindName("chkCSR")
    $chkXDC = $window.FindName("chkXDC")
    $chkPowerStatus = $window.FindName("chkPowerStatus")
    $btnRetrieve = $window.FindName("btnRetrieve")
    $dataGrid = $window.FindName("dataGrid")
    $progressBar = $window.FindName("progressBar")
    $btnExport = $window.FindName("btnExport")
    $btnClose = $window.FindName("btnClose")

    # Function to Retrieve PVS Data
    function Retrieve-PVSData {
    $progressBar.Visibility = "Visible"
    $progressBar.Value = 0
    $dataGrid.ItemsSource = $null  # Clear previous data

    # Check if Citrix PVS Module is Loaded
    if (-not (Get-Module -ListAvailable | Where-Object { $_.Name -like "Citrix.*" })) {
        [System.Windows.MessageBox]::Show("Citrix PVS PowerShell module is not installed or loaded.", "Error", "OK", "Error")
        $progressBar.Visibility = "Hidden"
        return
    }

    # Load Citrix PVS PowerShell module
    Asnp citrix* 

    # Retrieve PVS devices without MaxRecordCount
    try {
        $devices = Get-PVSDevice -ErrorAction Stop
        if (-not $devices) {
            [System.Windows.MessageBox]::Show("No PVS devices found.", "Information", "OK", "Information")
            $progressBar.Visibility = "Hidden"
            return
        }
    } catch {
        [System.Windows.MessageBox]::Show("Error retrieving devices: $_", "Error", "OK", "Error")
        $progressBar.Visibility = "Hidden"
        return
    }

    $deviceInfo = @()
    $totalDevices = $devices.Count
    $counter = 0

    foreach ($device in $devices) {
        $counter++
        $serverName = $device.Name
        $deviceCollection = $device.CollectionName

        $rebootValue = $csrServerValue = $xdcListValue = $powerStatusValue = "N/A"
        $powerState = if (Test-Connection -ComputerName $serverName -Count 1 -Quiet) { "On" } else { "Off" }

        try {
            $personality = Get-PVSDevicePersonality -DeviceName $serverName -ErrorAction Stop |
                           Select-Object -ExpandProperty DevicePersonality
        } catch {
            $personality = @()
        }

        if ($personality) {
            if ($chkReboot.IsChecked) {
                $rebootValue = ($personality | Where-Object { $_.Name -eq "Reboot" } | Select-Object -ExpandProperty Value) -join ", "
                if (-not $rebootValue) { $rebootValue = "N/A" }
            }

            if ($chkCSR.IsChecked) {
                $csrServerValue = ($personality | Where-Object { $_.Name -eq "CSAServer" } | Select-Object -ExpandProperty Value) -join ", "
                if (-not $csrServerValue) { $csrServerValue = "N/A" }
            }

            if ($chkXDC.IsChecked) {
                $xdcListValue = ($personality | Where-Object { $_.Name -eq "XDC_LIST" } | Select-Object -ExpandProperty Value) -join ", "
                if (-not $xdcListValue) { $xdcListValue = "N/A" }
            }
        }

        $obj = [ordered]@{
            ServerName       = $serverName
            DeviceCollection = $deviceCollection
            PowerState       = $powerState  # Add power state here
        }
        if ($chkReboot.IsChecked) { $obj["RebootDay"] = $rebootValue }
        if ($chkCSR.IsChecked) { $obj["CSRServer"] = $csrServerValue }
        if ($chkXDC.IsChecked) { $obj["XDCServer"] = $xdcListValue }

        $deviceInfo += New-Object PSObject -Property $obj

        $progressBar.Value = ($counter / $totalDevices) * 100
    }

    $dataGrid.ItemsSource = $deviceInfo
    [System.Windows.MessageBox]::Show("Data retrieval complete!", "Success", "OK", "Information")

    $progressBar.Value = 100
    Start-Sleep -Seconds 1
    $progressBar.Visibility = "Hidden"
}

    # Function to Export Data to CSV
    function Export-ToCSV {
        if ($dataGrid.ItemsSource -eq $null -or $dataGrid.ItemsSource.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No data available to export.", "Warning", "OK", "Warning")
            return
        }

        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = "CSV Files (*.csv)|*.csv"
        $dialog.Title = "Save CSV File"
        $dialog.FileName = "PVS_Devices.csv"

        if ($dialog.ShowDialog() -eq "OK") {
            $csvPath = $dialog.FileName
            $dataGrid.ItemsSource | Export-Csv -Path $csvPath -NoTypeInformation -Force
            [System.Windows.MessageBox]::Show("Data exported successfully to:$csvPath", "Export Complete", "OK", "Information")
        }
    }

    # Button Click Events
    $btnRetrieve.Add_Click({ Retrieve-PVSData })
    $btnExport.Add_Click({ Export-ToCSV })
    $btnClose.Add_Click({ $window.Close() })

    # Show Window
    $window.ShowDialog()

} elseif (Is-DeliveryController) {
    # If it's a Delivery Controller, run the Delivery Controller-related script
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName "System.Windows.Forms"  # Load the necessary assembly for the SaveFileDialog

    [xml]$XAML = @"
    <Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Citrix VDA Status Retrieval" Height="400" Width="650"
        WindowStartupLocation="CenterScreen">
    <Grid>
        <TextBlock Text="Select What Details to Retrieve:" FontSize="14" Margin="10,10,0,0" HorizontalAlignment="Left" VerticalAlignment="Top"/>
        <CheckBox Name="chkMachineName" Content="Machine Name" IsChecked="True" Margin="10,40,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkMachineCatalog" Content="Machine Catalog" Margin="10,70,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkDeliveryGroup" Content="Delivery Group" Margin="10,100,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkRegistrationState" Content="Registration State" Margin="10,130,0,0" VerticalAlignment="Top"/>
        <CheckBox Name="chkInMaintenanceMode" Content="In Maintenance Mode" Margin="10,160,0,0" VerticalAlignment="Top"/>
        <ProgressBar Name="progressBar" Height="20" Width="600" Margin="10,230,0,0" VerticalAlignment="Top" Visibility="Hidden"/>
        <DataGrid Name="dataGrid" Margin="10,260,10,60" AutoGenerateColumns="True"/>
        
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="10,190,10,10">
            <Button Name="btnRetrieve" Content="Retrieve Data" Width="150" Height="30" Margin="10,0" VerticalAlignment="Top"/>
            <Button Name="btnExport" Content="Export to CSV" Width="150" Height="30" Margin="10,0" VerticalAlignment="Top"/>
            <Button Name="btnClose" Content="Close" Width="100" Height="30" Margin="10,0" VerticalAlignment="Top"/>
        </StackPanel>
        
    </Grid>
</Window>
"@

    # Load XAML and bind controls
    $reader = (New-Object System.Xml.XmlNodeReader $XAML)
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Access UI Elements
    $chkMachineName = $window.FindName("chkMachineName")
    $chkMachineCatalog = $window.FindName("chkMachineCatalog")
    $chkDeliveryGroup = $window.FindName("chkDeliveryGroup")
    $chkRegistrationState = $window.FindName("chkRegistrationState")
    $chkInMaintenanceMode = $window.FindName("chkInMaintenanceMode")
    $btnRetrieve = $window.FindName("btnRetrieve")
    $dataGrid = $window.FindName("dataGrid")
    $progressBar = $window.FindName("progressBar")
    $btnExport = $window.FindName("btnExport")
    $btnClose = $window.FindName("btnClose")

    # Function to Retrieve XDC Data
    function Retrieve-BrokerMachineData {
        $progressBar.Visibility = "Visible"
        $progressBar.Value = 0
        $dataGrid.ItemsSource = $null  # Clear previous data

        # Check if Citrix Broker module is loaded
        if (-not (Get-Module -ListAvailable | Where-Object { $_.Name -like "Citrix.*" })) {
            [System.Windows.MessageBox]::Show("Citrix PowerShell module is not installed or loaded.", "Error", "OK", "Error")
            $progressBar.Visibility = "Hidden"
            return
        }

        # Load Citrix PowerShell module
        Asnp citrix*

        # Retrieve Broker Machine data with -MaxRecordCount to retrieve more records
        try {
            $machines = Get-BrokerMachine -MaxRecordCount 2000 | Select-Object @{
                Name="MachineName"; 
                Expression={$_.MachineName -replace '^.*\\', ''}
            }, CatalogName, DesktopGroupName, RegistrationState, InMaintenanceMode -ErrorAction Stop

            if (-not $machines) {
                [System.Windows.MessageBox]::Show("No Broker Machines found.", "Information", "OK", "Information")
                $progressBar.Visibility = "Hidden"
                return
            }
        } catch {
            [System.Windows.MessageBox]::Show("Error retrieving Broker Machine data: $_", "Error", "OK", "Error")
            $progressBar.Visibility = "Hidden"
            return
        }

        $machineInfo = @()
        $totalMachines = $machines.Count
        $counter = 0

        foreach ($machine in $machines) {
            $counter++
            $machineName = $machine.MachineName
            $catalogName = $machine.CatalogName
            $desktopGroup = $machine.DesktopGroupName
            $registrationState = $machine.RegistrationState
            $inMaintenanceMode = $machine.InMaintenanceMode

            $obj = [ordered]@{}

if ($chkMachineName.IsChecked) { $obj["MachineName"] = $machineName }
if ($chkMachineCatalog.IsChecked) { $obj["CatalogName"] = $catalogName }
if ($chkDeliveryGroup.IsChecked) { $obj["DesktopGroup"] = $desktopGroup }
if ($chkRegistrationState.IsChecked) { $obj["RegistrationState"] = $registrationState }
if ($chkInMaintenanceMode.IsChecked) { $obj["InMaintenanceMode"] = $inMaintenanceMode }

            $machineInfo += New-Object PSObject -Property $obj

            $progressBar.Value = ($counter / $totalMachines) * 100
        }

        $dataGrid.ItemsSource = $machineInfo
        [System.Windows.MessageBox]::Show("Data retrieval complete!", "Success", "OK", "Information")

        $progressBar.Value = 100
        Start-Sleep -Seconds 1
        $progressBar.Visibility = "Hidden"
    }

    # Function to Export Data to CSV
    function Export-ToCSV {
        if ($dataGrid.ItemsSource -eq $null -or $dataGrid.ItemsSource.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No data available to export.", "Warning", "OK", "Warning")
            return
        }

        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = "CSV Files (*.csv)|*.csv"
        $dialog.Title = "Save CSV File"
        $dialog.FileName = "Broker_MachineData.csv"

        if ($dialog.ShowDialog() -eq "OK") {
            $csvPath = $dialog.FileName
            $dataGrid.ItemsSource | Export-Csv -Path $csvPath -NoTypeInformation -Force
            [System.Windows.MessageBox]::Show("Data exported successfully to:$csvPath", "Export Complete", "OK", "Information")
        }
    }

    # Button Click Events
    $btnRetrieve.Add_Click({ Retrieve-BrokerMachineData })
    $btnExport.Add_Click({ Export-ToCSV })
    $btnClose.Add_Click({ $window.Close() })

    # Show Window
    $window.ShowDialog()

} else {
    Write-Host "This script should be run on either a Citrix PVS server or Citrix Delivery Controller."
}