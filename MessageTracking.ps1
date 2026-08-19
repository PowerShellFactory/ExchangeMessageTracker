#   ****************************************************************
#   * DO NOT USE IN A PRODUCTION ENVIRONMENT UNTIL YOU HAVE TESTED *
#   * THOROUGHLY IN A LAB ENVIRONMENT. USE AT YOUR OWN RISK.  IF   *
#   * YOU DO NOT UNDERSTAND WHAT THIS SCRIPT DOES OR HOW IT WORKS, *
#   * DO NOT USE IT OUTSIDE OF A SECURE, TEST SETTING.             *
#   ****************************************************************

<#
.SYNOPSIS
    Exchange Message Tracker

.DESCRIPTION
    Exchange Message Tracker

.NOTES
    Autor  : Andreas Werner
    Date   : 18.08.2026
    Version: 1.0.0

#>


#region - - - - -   P A R A M E T E R    - - - - -

[PSCustomObject] $parameter = [PSCustomObject] @{       
    MainForm         = Join-Path -Path $PSScriptRoot -ChildPath '\xaml\MainForm.xaml'
    GetMessageDetail = Join-Path -Path $PSScriptRoot -ChildPath '\xaml\GetMessageDetail.xaml'
    Style            = Join-Path -Path $PSScriptRoot -ChildPath '\config\Style.json'
    Configuration    = Join-Path -Path $PSScriptRoot -ChildPath '\config\MessageTracking.json'
    ModuleRoot       = Join-Path -Path $PSScriptRoot -ChildPath '\module'
    ExportRoot       = Join-Path -Path $PSScriptRoot -ChildPath '\export'
} 

$pad = 40

#endregion


#  +--------------------------------------------------------+
#  |   = = = = =   S T A R T   -   S C R I P T   = = = =    |
#  +--------------------------------------------------------+

Clear-Host
$ErrorActionPreference = 'Stop'
$WarningPreference     = 'SilentlyContinue'

#region Import modules
    Write-Host 'Import PowerShell modules' -BackgroundColor DarkCyan -ForegroundColor White
    Get-ChildItem -Path $parameter.ModuleRoot -File -Filter "*.psm1" | ForEach-Object{
        Write-Host " -> $($_.Name)"  -NoNewline
            try 
            {
                Import-Module -Name $_.FullName -Force -ErrorAction Stop
                Write-Host ' - OK' -ForegroundColor Green
            }
            catch
            {
                Write-Host ' - Error' -ForegroundColor Red
                break
            }        
    }
#endregion

Write-Host ''

#region Import JSON files
    Write-Host 'Import JSON files' -BackgroundColor DarkCyan -ForegroundColor White
    try
    {    
        Write-Host ' -> Config.json file ' -NoNewline       
            [PSCustomObject] $config = Import-JSON_File -FilePath $($parameter.Configuration)
        Write-Host '- OK' -ForegroundColor Green
        
    }
    catch
    {
        Write-Host $Error[0].Exception.Message
        break
    }

    try
    {    
        Write-Host ' -> Style.json file ' -NoNewline         
            [PSCustomObject] $style = Import-JSON_File -FilePath $($parameter.Style)
        Write-Host ' - OK' -ForegroundColor Green
        
    }
    catch
    {
        Write-Host $Error[0].Exception.Message
        end
    }
#endregion

Write-Host ''

#region Add shared assemblies
    try
    {
        [System.Reflection.Assembly]::LoadWithPartialName('PresentationFramework') | Out-Null
        [System.Reflection.Assembly]::LoadWithPartialName('PresentationCore')      | Out-Null
        [System.Reflection.Assembly]::LoadWithPartialName('WindowsBase')           | Out-Null
    }
    catch
    {
        Write-Host $Error[0].Exception.Message -BackgroundColor Red -ForegroundColor White
        end
    }
#endregion

#region MainForm - Read XAML and set PS-Variable
    [xml] $xaml = Get-WPS_MainForm
    
    $reader = [System.Xml.XmlNodeReader]::new($xaml)

    try
    {
        $MainForm = [Windows.Markup.XamlReader]::Load( $reader )
    }
    catch
    {
        Write-Host "Unable to load Windows.Markup.XamlReader. Some possible causes for this problem include:"
        write-host ".NET Framework is missing PowerShell must be launched with PowerShell -sta, invalid XAML code was encountered."
        Write-Host $Error[0].Exception.Message -BackgroundColor Red -ForegroundColor White
        exit
    }
    
    # Store Form Objects In PowerShell
        $xaml.SelectNodes("//*[@Name]") | ForEach-Object{
        Set-Variable -Name ($_.Name) -Value $MainForm.FindName($_.Name)        
    }
#endregion

#region Ribbon image source
    $rbtnSearch.LargeImageSource      = Join-Path -Path $PSScriptRoot -ChildPath '\images\Lupe.png'
    $rbtnClose.LargeImageSource       = Join-Path -Path $PSScriptRoot -ChildPath '\images\Close.png'
    $rbtnClearFilter.LargeImageSource = Join-Path -Path $PSScriptRoot -ChildPath '\images\Clean.png'
    $rbtnCsvExport.LargeImageSource   = Join-Path -Path $PSScriptRoot -ChildPath '\images\ExportCSV.png'
#endregion
    
#region Datatable - MessageTracking
    $dtMessageTracking = New-Object System.Data.DataTable

    $dgMessageTracking.DataContext

    [System.Array] $columnsMessageTracking = 
    @(
        "Timestamp"
        "Subject"
        "EventId"
        "Source"
        "Sender"
        "Recipients"
        "MessageId"
        "ClientHostname"
        "ServerHostname"
        "SourceContext"
        "ConnectorId"
        "RecipientStatus"         
    )

    $dtMessageTracking.Columns.AddRange($columnsMessageTracking)
    $dgMessageTracking.ItemsSource = $dtMessageTracking.DefaultView
#endregion    

# Set GUI defaults 
    Set-GuiDefaults

# Set Exchange Server list    
    List-ExchangeServerGUI
    
#region Start time
    $chkTimeStart.Add_Click({
        $dpStart.IsEnabled       = $chkTimeStart.isChecked
        $txtStartHour.IsEnabled  = $chkTimeStart.isChecked
        $txtStartMin.IsEnabled   = $chkTimeStart.isChecked
        
        if($chkTimeStart.isChecked)
        {
            $txtStartHour.Background = 'Cornsilk'
            $txtStartMin.Background  = 'Cornsilk'
        }
        else
        {
            $txtStartHour.Background = 'White'
            $txtStartMin.Background  = 'White'
        }
    })

    $txtStartHour.Add_PreviewTextInput({
        param($sender, $e)

        # Ergebnis-Text simulieren (aktueller Text + neue Eingabe an Cursor-Position)
        $caret = $sender.CaretIndex
        $neuerText = $sender.Text.Insert($caret, $e.Text)

        if ($neuerText -notmatch '^[0-9]{1,2}$') {
            $e.Handled = $true
            return
        }

        if ([int]$neuerText -gt 23) {
            $e.Handled = $true
        }
    })

    $txtStartMin.Add_PreviewTextInput({
        param($sender, $e)

        # Ergebnis-Text simulieren (aktueller Text + neue Eingabe an Cursor-Position)
        $caret = $sender.CaretIndex
        $neuerText = $sender.Text.Insert($caret, $e.Text)

        if ($neuerText -notmatch '^[0-9]{1,2}$') {
            $e.Handled = $true
            return
        }

        if ([int]$neuerText -gt 59) {
            $e.Handled = $true
        }
    })
#endregion

#region End time
    $chkTimeEnd.Add_Click({       
        $dpEnd.IsEnabled       = $chkTimeEnd.isChecked
        $txtEndHour.IsEnabled  = $chkTimeEnd.isChecked
        $txtEndMin.IsEnabled   = $chkTimeEnd.isChecked

        if($chkTimeEnd.isChecked)
        { 
            $txtEndHour.Background = 'Cornsilk'
            $txtEndMin.Background  = 'Cornsilk'
        }
        else
        {
            $txtEndHour.Background = 'White'
            $txtEndMin.Background  = 'White'
        }
    })

    $txtEndHour.Add_PreviewTextInput({
        param($sender, $e)

        # Ergebnis-Text simulieren (aktueller Text + neue Eingabe an Cursor-Position)
        $caret = $sender.CaretIndex
        $neuerText = $sender.Text.Insert($caret, $e.Text)

        if ($neuerText -notmatch '^[0-9]{1,2}$') {
            $e.Handled = $true
            return
        }

        if ([int]$neuerText -gt 23) {
            $e.Handled = $true
        }
    })

    $txtEndMin.Add_PreviewTextInput({
        param($sender, $e)

        # Ergebnis-Text simulieren (aktueller Text + neue Eingabe an Cursor-Position)
        $caret = $sender.CaretIndex
        $neuerText = $sender.Text.Insert($caret, $e.Text)

        if ($neuerText -notmatch '^[0-9]{1,2}$') {
            $e.Handled = $true
            return
        }

        if ([int]$neuerText -gt 59) {
            $e.Handled = $true
        }
    })
#endregion

# Button - Start searching     
    $rbtnSearch.Add_Click({ Start-MessageTracking })
    $dgMessageTracking.Add_MouseDoubleClick({ Get-MessageDetail })

# Button - CSV export    
    $rbtnCsvExport.Add_Click({ ExportTo-CsvFile -ExportPath $($parameter.ExportRoot) })

# Button - Reset    
    $rbtnClearFilter.Add_Click({ Clear-DisplayFilter })
       
# List Exchange Server    
    $chkSelectAll.Add_Click({ $lstExchangeServer.Items | ForEach-Object { $_.isChecked = $chkSelectAll.isChecked} })

# TreeView - Message tracking
    $treMessageTracking.Add_PreviewMouseUp({ 

        [System.Array] $entry = $treMessageTracking.SelectedItem.Tag -split ';'

        switch ($entry[0])
        {        
            'Recipients' 
            {
                $txtSender.Text    = ''
                $txtRecipient.Text = $entry[1]
            }
            'Sender' 
            {
                $txtRecipient.Text = ''
                $txtSender.Text    = $entry[1]
            }
        }
    })
    
# Close  PowerShell application
    $rbtnClose.Add_Click({ $MainForm.Close() })

#region FILTER
    $txtSender.Add_TextChanged({            Set-DataTable_Filter })
    $txtRecipient.Add_TextChanged({         Set-DataTable_Filter })
    $txtSubject.Add_TextChanged({           Set-DataTable_Filter })
    $txtMessageID.Add_TextChanged({         Set-DataTable_Filter })
    $txtIntMessageID.add_SelectionChanged({ Set-DataTable_Filter })
    $cboEventID.add_SelectionChanged({      Set-DataTable_Filter })

    $txtSource.Add_TextChanged({            Set-DataTable_Filter })
    $txtClientHostname.Add_TextChanged({    Set-DataTable_Filter })
    $txtServerHostname.Add_TextChanged({    Set-DataTable_Filter })
    $txtSourceContext.Add_TextChanged({     Set-DataTable_Filter })
    $txtConnectorId.Add_TextChanged({       Set-DataTable_Filter })
    $txtRecipientStatus.Add_TextChanged({   Set-DataTable_Filter })

    $cboSender.Add_SelectionChanged({          Set-DataTable_Filter })
    $cboRecipient.Add_SelectionChanged({       Set-DataTable_Filter })
    $cboSubject.Add_SelectionChanged({         Set-DataTable_Filter })
    $cboMessageID.Add_SelectionChanged({       Set-DataTable_Filter })
    $cboIntMessageID.Add_SelectionChanged({    Set-DataTable_Filter })
    $cboEventID2.Add_SelectionChanged({        Set-DataTable_Filter })
    
    $cboSource.Add_SelectionChanged({          Set-DataTable_Filter })
    $cboClientHostname.Add_SelectionChanged({  Set-DataTable_Filter })
    $cboServerHostname.Add_SelectionChanged({  Set-DataTable_Filter })
    $cboSourceContext.Add_SelectionChanged({   Set-DataTable_Filter })
    $cboConnectorId.Add_SelectionChanged({     Set-DataTable_Filter })
    $cboRecipientStatus.Add_SelectionChanged({ Set-DataTable_Filter })
#endregion    

#  Show Dialog
    $MainForm.WindowState = "Maximized"
    $MainForm.ShowDialog() | Out-Null


