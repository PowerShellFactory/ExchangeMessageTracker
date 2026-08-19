#
# Autor   : Andreas werner
# Date    : 27.06.2025
# Version : 3.4
#


function Get-WPS_MainForm
{
[CmdletBinding()]
param()

#Load Tab items
    $mainFormTabItem = Get-ChildItem -Path $($parameter.MainForm) -Filter '*.xaml' | Get-Content -Encoding utf8

    $windowResourcesStyle = Get-WindowResourcesStyle -Style $Style

[xml] $xamlMainForm = @"
<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:ribbon="clr-namespace:System.Windows.Controls.Ribbon;assembly=System.Windows.Controls.Ribbon"

        FontFamily            = "$($Style.MainForm.FontFamily)"
        Title                 = "$($config.Title) - Version: $($config.Version)"
        ShowInTaskbar         = "$($Style.MainForm.ShowInTaskbar)"
        WindowStartupLocation = "$($Style.MainForm.WindowStartupLocation)"
        ResizeMode            = "$($Style.MainForm.ResizeMode)"       
        Background            = "$($Style.MainForm.Background)" 
>

    <Window.Resources>        
        $windowResourcesStyle 
    </Window.Resources>
    
    $($mainFormTabItem)

    
</Window>
"@

    return $xamlMainForm

}

function Save-FileDialog
{
param
(
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [System.String] $initialDirectory = $scriptRoot
)

    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
    $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.initialDirectory = $initialDirectory
        $saveFileDialog.filter           = "CSV (*.csv)| *.csv"
        $saveFileDialog.Title            = 'Export CSV file'
        $saveFileDialog.ShowDialog() | Out-Null

    $csvFilePath = $saveFileDialog.filename

    Write-Output $csvFilePath
}

function ExportTo-CsvFile
{
param
(
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [System.String] $ExportPath
)

    [System.String] $exportCsvFilePath = Save-FileDialog -initialDirectory $ExportPath

    if( $exportCsvFilePath )
    {
        # Export
        "Result export to CSV file -> $exportCsvFilePath" | Set-StatusMessage -Severity WAR
        try 
        {
            $dtMessageTracking.DefaultView | Export-Csv -Path $exportCsvFilePath -Delimiter $($config.CSV.Delimiter) -Encoding $($config.CSV.Encoding) -NoTypeInformation -Force 
            "Succssfully - CSV export" | Set-StatusMessage
        }
        catch
        {
            $Global:Error[0].Exception.Message | Set-StatusMessage -Severity ERR
        }
    }
}

function Import-JSON_File
{
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [Alias("FullName")]
    [System.String] $FilePath,

    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [System.Text.Encoding] $Encoding = [System.Text.Encoding]::UTF8,

    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [Switch] $ValidateFilePath
)

Begin 
{ 
    Write-Verbose "Start - Import JSON file"
}

Process
{
    #region Test file path
        if($ValidateFilePath)
        {
            Write-Verbose "Test file path : $FilePath"
            if( -not( Test-Path -Path $FilePath )) 
            {
                Write-Warning "JSON file not found" -Verbose
                return
            }
            Write-Verbose "OK - File found"
        }
    #endregion
    
    #region Import JSON file
        try 
        {
            Write-Verbose 'Import JSON file...'
            Write-Verbose "  Encoding : $Encoding"
            Write-Verbose "  FilePath : $FilePath"

            $json = Get-Content -Raw -Encoding UTF8 -Path $FilePath | ConvertFrom-Json -ErrorAction Stop 
            Write-Verbose "OK - Import JSON file successfully"
            
            return $json
        }
        catch 
        {
            $errMsg = $Error[0].Exception.Message
            Write-Host $errMsg -BackgroundColor Red -ForegroundColor White
            
            return
        }
    #endregion
}

End 
{ 
    Write-Verbose "Finish - Import JSON file"
}

}

function Convert-ArrayToString
{
[CmdletBinding()]
param
(       
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [System.Array] $array
)

    [System.String] $string = ''
    [System.Int16]  $count  = $array.Count
    [System.Int16]  $a      = 0


    if($count -eq 0) { return  $string }

    if($count -eq 1) { return  $array[0] }


    for( $i=0; $i -lt $count; $i++)
    {
        $a++
        [System.String] $item = $array[$i]; $item = $item.Trim()

        if($a -eq 3) { $item += ",`r`n" ; $a = 0;  $string += $item }
        else { $string += $item + ', ' }
    }
        
    [system.int32] $len = $string.Length -2

    $string = $string.Substring(0, $len)
    
    return $string
}

function List-ExchangeServerGUI
{
[CmdletBinding()]
param 
(
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [System.String] $DomainController
)

Begin
{
    [scriptblock] $sbTestConect = {
    param ([System.String] $Server)
        $result = [pscustomobject] @{ Server = $Server; Connect = $true }

        #region PowerShell session options
            [hashtable] $psoParam =
            @{
                NoMachineProfile    = $true
                SkipCACheck         = $true
                SkipCNCheck         = $true
                SkipRevocationCheck = $true
                ErrorAction         = "Stop"              
            }
                        
            try   { [System.Management.Automation.Remoting.PSSessionOption] $pso = New-PSSessionOption @psoParam }
            catch { return }           
        #endregion

        try { $targetSession = New-PSSession -ComputerName $Server -SessionOption $pso -ErrorAction Stop }
        catch { $result.Connect = $False}

        $targetSession | Remove-PSSession -ErrorAction SilentlyContinue

        $result
    }
}

Process 
{
    #region Find configuration naming contex
        $rootDSE = [System.DirectoryServices.DirectoryEntry]("LDAP://$([System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().Name)/RootDSE")
        [System.String] $configNC = $rootDSE.configurationNamingContext
    #endregion    

    #region Exchange organisation
        [System.String] $searchRoot1 = 'LDAP://CN=Microsoft Exchange,CN=Services,{0}' -f $configNC

        $searcher1 = [System.DirectoryServices.DirectorySearcher]""
            $searcher1.Filter     = "(objectClass=msExchOrganizationContainer)"
            $searcher1.SearchRoot = [System.DirectoryServices.DirectoryEntry] $searchRoot1
            $searcher1.SearchScope = 'OneLevel'
        $result1 = $searcher1.FindAll() 

        [System.String] $msExchOrg = $result1.Properties.cn
    #endregion

    Write-Host "Exchange organisation : $msExchOrg " -BackgroundColor White -ForegroundColor black
            
    #region List Exchange Server in organisation
        [System.Collections.ArrayList] $msExchServerList = @()
        [System.String] $searchRoot2 =  "LDAP://CN=Servers,CN=Exchange Administrative Group (FYDIBOHF23SPDLT),CN=Administrative Groups,CN={0},CN=Microsoft Exchange,CN=Services,{1}" -f $msExchOrg, $configNC

        $searcher2 = [System.DirectoryServices.DirectorySearcher]""
            $searcher2.Filter     = "(objectClass=msExchExchangeServer)"
            $searcher2.SearchRoot = [System.DirectoryServices.DirectoryEntry] $searchRoot2
            $searcher2.SearchScope = 'OneLevel'

            $null = $searcher2.PropertiesToLoad.Add('msExchMDBAvailabilityGroupLink')
            $null = $searcher2.PropertiesToLoad.Add('Name')            
        $result2 = $searcher2.FindAll() 

        [System.String] $searchRoot3 = 'LDAP://{0}' -f [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain().Name

        foreach ($server in $result2.Properties)
        {
            [System.String] $dagName = ''
            
            # Search DAG membership
                if ( [System.String] $server["msExchMDBAvailabilityGroupLink"] -match "\ACN=([A-Za-z0-9-_]*)" )
                { $dagName = $Matches[1]}
            
            # search DNS host name
                $searcher3 = [System.DirectoryServices.DirectorySearcher]""
                    $searcher3.Filter      = "(&(objectClass=computer)(name={0}))" -f  [System.String] $server["Name"]
                    $searcher3.SearchRoot  = [System.DirectoryServices.DirectoryEntry] $searchRoot3
                    $searcher3.SearchScope = 'Subtree'
                    $searcher3.PropertiesToLoad.Add('dNSHostName') | Out-Null
                 $result3 = $searcher3.FindAll() 
            
            # Result
                $entry = [pscustomobject] @{
                    MsExchOrganisation  = $msExchOrg
                    MsExchServerFQDN    = [System.String] $result3.Properties["dnshostname"]
                    MsExchServerNetBIOS = [System.String] $server["Name"]
                    DAG                 = $dagName
                }

            $null = $msExchServerList.Add($entry)
        }
    #endregion

    #region Create PS runspaces pool
        [System.Int16] $poolMax = 4
        $runspacePool = [RunspaceFactory]::CreateRunspacePool(1,$poolMax)
        $runspacePool.Open()
        
        [System.Collections.ArrayList] $runspaces = @()

        foreach( $srv in $msExchServerList )
        { 
            $Runspace = [powershell]::Create().AddScript($sbTestConect)
                $null = $Runspace.AddArgument($($srv.MsExchServerFQDN))                
            $Runspace.RunspacePool = $RunspacePool
            
            $rs   = [pscustomobject] @{ Runspace=$Runspace; State=$Runspace.BeginInvoke()}
            $null = $runspaces.Add($rs)
        }

        # Waite until all runspaces finished
            while ( $runspaces.State.IsCompleted -contains $False) { Start-Sleep -Milliseconds 10 }
        
            [System.Array] $connectionList += $runspaces | ForEach-Object { $_.Runspace.EndInvoke($_.State) }
          
        $runspacePool.Close()
    #endregion

    #region List all Exchange Server
        $lstExchangeServer.Items.Clear() 
  
        foreach( $con in $connectionList )
        { 
            $itm = [System.Windows.Controls.CheckBox]::New()

            [System.String] $srvNetBIOS = ($msExchServerList | Where-Object { $_.MsExchServerFQDN -eq $con.Server}).MsExchServerNetBIOS

            if( $con.Connect)
            {
                $itm.Content    = $srvNetBIOS
                $itm.IsChecked  = $true
                $itm.Tag        = $con.Server
                $itm.Foreground = 'Black' 
            }
            else
            {
                $itm.Content    = "{0} > Not available <" -f $srvNetBIOS
                    $itm.IsChecked  = $false
                    $itm.IsEnabled  = $false
                    $itm.Tag        = $con.Server
                    $itm.Foreground = 'Red'
                    $itm.FontWeight = "Bold"
            }
            
            $lstExchangeServer.Items.Add($itm) | Out-Null 
       }
    #endregion

  $groupboxExchangeServer.Header = "Exchange Server ($($msExchServerList.Count))"


    $chkSelectAll.isChecked = $true

  $groupboxExchangeServer.Header = "Exchange Server ($($lstExchangeServer.Items.Count))"

}

End
{

}

}

function Set-GuiDefaults
{
[CmdletBinding()]
param ()

begin {}

process
{
    [System.Array] $operator = @('Like', 'Not like')

    $dtMessageTracking.DefaultView.RowFilter = $null

    #region Datagrid
    #    $dgMessageTracking.Clear()
    #endregion

    #region Sender
        $txtSender.Text = ''
        $cboSender.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboSender.ItemsSource = $operator
        $cboSender.Text = $operator[0]
    #endregion
    
    #region Recipient
        $txtRecipient.Text = ''
        $cboRecipient.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboRecipient.ItemsSource = $operator
        $cboRecipient.Text = $operator[0]        
    #endregion

    #region Subject
        $txtSubject.Text = ''
        $cboSubject.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboSubject.ItemsSource = $operator
        $cboSubject.Text = $operator[0]
    #endregion

    #region MessageID
        $txtMessageID.Text= ''
        $cboMessageID.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboMessageID.ItemsSource = $operator
        $cboMessageID.Text = $operator[0]
    #endregion

    #region Start time
        $chkTimeStart.isChecked = $true        
        
        [System.Int32] $startTimeDif = -1 * ($config.StartTimeDifference.Hours * 60 + $config.StartTimeDifference.Minutes)
        $dpStart.Text = $(Get-Date).AddMinutes($startTimeDif) | Get-Date -Format F

        $txtStartHour.Text = $(Get-Date).AddMinutes($startTimeDif) | Get-Date -Format 'HH'
        $txtStartMin.Text  = $(Get-Date).AddMinutes($startTimeDif) | Get-Date -Format 'mm'
    #endregion
        
    #region End time
        $chkTimeEnd.isChecked = $false 
        $dpEnd.IsEnabled = $false       
        $dpEnd.Text = Get-Date -Format f
                        
        $txtEndHour.Text      = Get-Date -Format 'HH'
        $txtEndHour.IsEnabled = $false

        $txtEndMin.Text      = Get-Date -Format 'mm'
        $txtEndMin.IsEnabled = $false
    #endregion
               
    #region Event ID
        $cboEventID.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboEventID.ItemsSource = @($config.EventID.IDs)
        $cboEventID.Text        = $($config.EventID.Default)
       
       $cboEventID2.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
       $cboEventID2.ItemsSource = $operator
       $cboEventID2.Text = $operator[0]
    #endregion
        
    #region Internal Message ID
        $txtIntMessageID.Text = ''        
        $cboIntMessageID.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboIntMessageID.ItemsSource = $operator
        $cboIntMessageID.Text = $operator[0]
    #endregion

    #region Source
        $txtSource.Text = ''
        $cboSource.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboSource.ItemsSource = $operator
        $cboSource.Text = $operator[0]
    #endregion

    #region Client-Hostname
        $txtClientHostname.Text = ''
        $cboClientHostname.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboClientHostname.ItemsSource = $operator
        $cboClientHostname.Text = $operator[0]
    #endregion
    
    #region Server-Hostname
        $txtserverHostname.Text = ''
        $cboserverHostname.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboserverHostname.ItemsSource = $operator
        $cboserverHostname.Text = $operator[0]
    #endregion

    #region Source-Context
        $txtSourceContext.Text = ''
        $cboSourceContext.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboSourceContext.ItemsSource = $operator
        $cboSourceContext.Text = $operator[0]
    #endregion

    #region Connector-ID
        $txtConnectorId.Text = ''
        $cboConnectorId.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)
        $cboConnectorId.ItemsSource = $operator
        $cboConnectorId.Text = $operator[0]
    #endregion 

    #region Recipient-Status
        $txtRecipientStatus.Text = ''
        $cboRecipientStatus.ClearValue([System.Windows.Controls.ItemsControl]::ItemsSourceProperty)        
        $cboRecipientStatus.ItemsSource = $operator
        $cboRecipientStatus.Text = $operator[0]
    #endregion

}

end {}
    
}

function Clear-DisplayFilter
{
[CmdletBinding()]
param ()

begin {}

process
{
    
    # Sender
        $txtSender.Text = ''
            
    # Recipient
        $txtRecipient.Text = ''
       
    # Subject
        $txtSubject.Text = ''
            
    # MessageID
        $txtMessageID.Text= ''     
               
    # Event ID             
        $cboEventID.Text = $($config.EventID.Default)    
        
    # Internal Message ID
        $txtIntMessageID.Text = ''        
        
    # Source
        $txtSource.Text = ''
        
    #  Client-Hostname
        $txtClientHostname.Text = ''
        
    #  Server-Hostname
        $txtserverHostname.Text = ''
        
    #  Source-Context
        $txtSourceContext.Text = ''
        
    #  Connector-ID
        $txtConnectorId.Text = ''
        
    #  Recipient-Status
        $txtRecipientStatus.Text = ''   
        
    $dtMessageTracking.DefaultView.RowFilter = $null
}

end {}

}

function Set-DataTable_Filter
{
[CmdletBinding()]
param()

    [System.String] $filter = ''
    
    # S E N D E R
        [System.String] $sender = $txtSender.Text.Trim() 
        if($sender) { $filter += "(Sender $($cboSender.SelectedItem) '%$sender%') AND " }
    
    # R E C I P I E N T
        [System.String] $recipient = $txtRecipient.Text.Trim() 
        if($recipient) { $filter += "(Recipients $($cboRecipient.SelectedItem) '%$recipient%') AND " }
    
    # S U B J E C T
        [System.String] $subject = $txtSubject.Text.Trim()
        if($subject) { $filter += "(Subject $($cboSubject.SelectedItem) '%$subject%') AND " }

    # E V E N T   I D    
        [System.String] $eventID = $cboEventID.SelectedItem        
        if( $eventID -ne 'All') { [System.String] $filter += "(EventId $($cboEventID2.SelectedItem) '%$eventID%') AND " }
    
    # S O U R C E
        [System.String] $source = $txtSource.Text.Trim()
        if($source) { $filter += "(Source $($cboSource.SelectedItem) '%$source%') AND " }

    # M E S S A G E   I D 
        [System.String] $messageID = $txtMessageID.Text.Trim()
        if($messageID) { $filter += "(MessageId $($cboMessageID.SelectedItem) '%$messageID%') AND " }
    
    # I N T E R N A L   M E S S A G E   I D     
        [System.String] $intMessageID = $txtIntMessageID.Text.Trim()
        if($intMessageID) { $filter += "(IntMessageId $($cboIntMessageID.SelectedItem) '%$intMessageID%') AND " }

    # S O U R C E   C O N T E X T
        [System.String] $sourceContext = $txtSourceContext.Text.Trim()
        if($sourceContext) { $filter += "(SourceContext $($cboSourceContext.SelectedItem) '%$sourceContext%') AND " }
    
    # C L I E N T   H O S T N A M E
        [System.String] $clientHostname = $txtClientHostname.Text.Trim()
        if($clientHostname) { $filter += "(ClientHostname $($cboClientHostname.SelectedItem) '%$clientHostname%') AND " }
    
    # S E R V E R   H O S T N A M E
        [System.String] $serverHostname = $txtServerHostname.Text.Trim()
        if($serverHostname) { $filter += "(ServerHostname $($cboServerHostname.SelectedItem) '%$serverHostname%') AND " }

    # S O U R C E   C O N T E X T
        [System.String] $sourceContext = $txtSourceContext.Text.Trim()
        if($sourceContext) { $filter += "(SourceContext $($cboSourceContext.SelectedItem) '%$sourceContext%') AND " }
    
    # C O N N E C T O R   I D
        [System.String] $connectorId = $txtConnectorId.Text.Trim()
        if($connectorId) { $filter += "(ConnectorId $($cboConnectorId.SelectedItem) '%$connectorId%') AND " }
    
    # R E C I P I E N   S T A T U S
        [System.String] $recipientStatus = $txtRecipientStatus.Text.Trim()
        if($recipientStatus) { $filter += "(RecipientStatus $($cboRecipientStatus.SelectedItem) '%$recipientStatus%') AND " }
            

    if ($filter)
    {
        [System.Int32] $filterLenght = $filter.Length -5
        $filter = $filter.Substring(0,$filterLenght)
    }
    
    $dtMessageTracking.DefaultView.RowFilter = $filter

    # $dgMessageTracking.ItemsSource = $dtMessageTracking.DefaultView 
    $txtStatusInfo.Text = "Messages : $($dgMessageTracking.Items.Count)"
    
}

function Get-MessageTrackingParameter
{
 [CmdletBinding()]
param()
   
    [hashtable] $trackingParam = @{ ResultSize = 'unlimited' }
    
    # Sender
        [System.String] $txtSenderVal = $txtSender.Text.Trim()        
        if($txtSenderVal) { $trackingParam.Add('Sender',$txtSenderVal) }

    # Recipients
        [System.String] $txtRecipientVal = $txtRecipient.Text.Trim()        
        if($txtRecipientVal) { $trackingParam.Add('Recipients',$txtRecipientVal) }

    # Subject
        [System.String] $txtSubjectVal = $txtSubject.Text.Trim()        
        if($txtSubjectVal) { $trackingParam.Add('Subject',$txtSubjectVal) }

    # Start time        
        if($chkTimeStart.isChecked ) 
        {
            if( $($txtStartHour.Text).Trim() ) { $hour = $txtStartHour.Text } 
            else { $txtStartHour.Text = "0"; $hour = "0" } 

            if( $($txtStartMin.Text).Trim() )  { $min  = $txtStartMin.Text } 
            else  { $txtStartMin.Text= "0"; $min = "0" } 
                        
            
            $tempStartTime = "{0} {1}:{2}" -f $($dpStart.Text),$hour,$min
            $startTime     = Get-Date -Date $tempStartTime             
            $trackingParam.Add('Start',$startTime) 
        }
    
    # End time        
        if( $chkTimeEnd.isChecked ) 
        {
            if( $($txtEndHour.Text).Trim() ) { $hour = $txtEndHour.Text } 
            else { $txtEndHour.Text = "0"; $hour = "0" } 

            if( $($txtEndMin.Text).Trim() )  { $min  = $txtEndMin.Text } 
            else  { $txtEndMin.Text= "0"; $min = "0" } 
                        
            
            $tempEndTime = "{0} {1}:{2}" -f $($dpEnd.Text),$hour,$min
            $endTime     = Get-Date -Date $tempEndTime             
            $trackingParam.Add('End',$endTime) 
        }
    
    # Event ID        
        [System.String] $curEventID = $cboEventID.Text.Trim()
        if($curEventID -ne 'All') { $trackingParam.Add('EventID',$curEventID) }

    # Message ID
        [System.String] $txtMessageIDVal = $txtMessageID.Text.Trim()        
        if($txtMessageIDVal) { $trackingParam.Add('MessageID',$txtMessageIDVal) }

    # Internal message ID
        [System.String] $txtIntMessageID = $txtIntMessageID.Text.Trim()        
        if($txtMessageIDVal) { $trackingParam.Add('InternalMessageID',$txtIntMessageID) }

    
    return $trackingParam
}

function Get-MessageDetail
{
[CmdletBinding()]
param ()

Begin {}

Process
{
    Add-Type -AssemblyName PresentationFramework

# XAML laden
    [xml] $xamlGetMessageDetail = Get-Content -Encoding utf8 -Path $parameter.GetMessageDetail
    $reader = (New-Object System.Xml.XmlNodeReader ([xml]$xamlGetMessageDetail))
    $getMessageDetail = [Windows.Markup.XamlReader]::Load($reader)

# Load controls   
    $xamlGetMessageDetail.SelectNodes("//*[@Name]") | 
    ForEach-Object { Set-Variable -Name ($_.Name) -Value $getMessageDetail.FindName($_.Name) }
   

    $txtTimestamp.Text       = $dgMessageTracking.SelectedItems.Timestamp
    $txtSubject.Text         = ($dgMessageTracking.SelectedItems.Subject).Replace("`r`n",'')
    $txtEventId.Text         = $dgMessageTracking.SelectedItems.EventId
    $txtSource.Text          = $dgMessageTracking.SelectedItems.Source
    $txtSender.text          = $dgMessageTracking.SelectedItems.Sender   
    $txtMessageId.Text       = $dgMessageTracking.SelectedItems.MessageId
    $txtClientHostname.Text  = $dgMessageTracking.SelectedItems.ClientHostname
    $txtServerHostname.Text  = $dgMessageTracking.SelectedItems.ServerHostname
    $txtSourceContext.Text   = $dgMessageTracking.SelectedItems.SourceContext  
    $txtConnectorId.Text     = $dgMessageTracking.SelectedItems.ConnectorId
    $txtRecipientStatus.Text = $dgMessageTracking.SelectedItems.RecipientStatus
    
    foreach($rec in $($dgMessageTracking.SelectedItems.Recipients -split ',' | Where-Object { $_.Trim() } ))
    {        
        $txtRecipients.Text += $rec.Trim() + [System.Environment]::NewLine
    }

    [System.String] $tmpRecS  = ($dgMessageTracking.SelectedItems.RecipientStatus).Replace("`r`n",'')
    [System.Array] $arrayRecS = $tmpRecS.Split(',').Trim() | Where-Object { $_.Trim() }
    
    $txtRecipientStatus.Text = ''

    foreach($recS in $arrayRecS )
    {        
        $txtRecipientStatus.Text += $recS + [System.Environment]::NewLine
    }

# Close-Button
    $cmdGetMsgDetailsClose.Add_Click({ $getMessageDetail.Close() })

# Dialog modal view
    $result = $getMessageDetail.ShowDialog()

}

End { }

}

function Get-WindowResourcesStyle
{
[CmdletBinding()]
param
(
    [Parameter(Mandatory=$true,ValueFromPipelineByPropertyName=$true)]
    [PSCustomObject] $Style
)

Begin 
{ 
    [System.String] $windowResourcesStyle = ''
}

Process
{    
    [System.Array] $styleNames =  $Style | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -ne 'MainForm' }     

    ForEach( $styleName in $styleNames.Name)
    {
        
        [System.String] $targetTypeStart = "<Style TargetType='$styleName'>"   
        [System.String] $targetTypeEnd   = "</Style>"
        [System.String] $Setters         = ""

         $Style.$styleName | Get-Member -MemberType NoteProperty | ForEach-Object{
            $property = $_.Name
            $value    = $Style.$styleName.$property

            $Setters += "<Setter Property='$property' Value='$value' />"
         }

         $windowResourcesStyle += $targetTypeStart + $Setters + $targetTypeEnd
    }
    
}

End 
{ 
    return $windowResourcesStyle
}

}

function Set-StatusMessage
{
[CmdletBinding()]
param 
(
    [Parameter(Mandatory=$false,ValueFromPipeline=$true,ParameterSetName="ID")]
    [System.String] $Message,
    
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
    [ValidateSet("OK","WAR","ERR")]
    [System.String] $Severity = 'OK' 
)
    switch($severity )
    {
        'OK'  { $staInfo.Background = $config.Severity.OK.Background  ; $txtStatusInfo.Foreground = $config.Severity.OK.Foreground  }
        'WAR' { $staInfo.Background = $config.Severity.WAR.Background ; $txtStatusInfo.Foreground = $config.Severity.WAR.Foreground }
        'ERR' { $staInfo.Background = $config.Severity.ERR.Background ; $txtStatusInfo.Foreground = $config.Severity.ERR.Foreground }
    }

    $txtStatusInfo.Text = $Message
    $MainForm.Dispatcher.Invoke([System.Action]{},'Background')

}

function Split-String
{
[CmdletBinding()]
param
(       
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [System.String] $string
)

    [System.String] $result    = ''
    [System.Int32]  $length     = $string.Length
    [System.Int16]  $iteration = 0
    [System.Int16]  $maxLenght = 60


    if($length -le $maxLenght) { return  $string }

    $iteration = [System.Math]::Ceiling( $length / $maxLenght ) 

    for( $i=0; $i -lt $iteration; $i++)
    {
        [System.Int16] $start     = $i * $maxLenght
        [System.Int16] $divLenght = $length - $start

        if( $divLenght -gt $maxLenght)
        {
            $result += $string.Substring($start,$maxLenght) + "`r`n"
        }
        else
        {
            $result += $string.Substring($start,$divLenght)
        }        
        
    }
        
    $result
}

function Start-MessageTracking
{
[CmdletBinding()]
param()    
    
    $dtMessageTracking.Clear()    
    $dgMessageTracking.ItemsSource = $dtMessageTracking.DefaultView
    
    # Tracking parameter    
        [hashtable] $trackingParam = Get-MessageTrackingParameter
    
    #region Validate selected Exchange Server list
        [System.Collections.ArrayList] $selectedExServer = @()
        $lstExchangeServer.Items | Where-Object { $_.IsChecked } | 
        ForEach-Object { $selectedExServer.Add($_.content) }

        if( $selectedExServer.count -le 0)
        {
            "No Exchange Server were selected" | Set-StatusMessage -Severity WAR
            return
        }
    #endregion

    #region Message tracking
        Write-Host "Start - Message tracking. Please wait..." -ForegroundColor Yellow 
        
        "Start - Tracking Server. Please wait..." | Set-StatusMessage -Severity WAR
        
        $MainForm.Dispatcher.Invoke([System.Action]{},'Background')
        
        $connectionUri = $selectedExServer | ForEach-Object{ "http://$_/PowerShell"  }
        $sessions = New-PSSession -ConfigurationName 'Microsoft.Exchange' -ConnectionUri $connectionUri -Authentication Kerberos
        
        # Search tracking infomation from Exchange server
        [scriptblock] $sb = 
        {
            param($trackingParam)

            Get-MessageTrackingLog @trackingParam
        }
                
        ForEach($trackingResult in $(Invoke-Command -Session $sessions -ScriptBlock $sb -ArgumentList $trackingParam ) )
        {
            try{
            $row = $dtMessageTracking.NewRow()
                $row.Timestamp       = $trackingResult.Timestamp | Get-Date -Format 'dd.MM.yyyy HH:mm:ss'
                $row.Subject         = if($trackingResult.MessageSubject) { $trackingResult.MessageSubject | Split-String } else { $null }
                $row.EventId         = $trackingResult.EventId
                $row.Source          = $trackingResult.Source            
                $row.Sender          = $trackingResult.Sender
                $row.Recipients      = Convert-ArrayToString -array $($trackingResult.Recipients)
                $row.MessageId       = $trackingResult.MessageId
                $row.ClientHostname  = $trackingResult.ClientHostname
                $row.ServerHostname  = $trackingResult.ServerHostname
                $row.SourceContext   = $trackingResult.SourceContext            
                $row.ConnectorId     = $trackingResult.ConnectorId
                $row.RecipientStatus = Convert-ArrayToString -array $( $trackingResult.RecipientStatus )
      
            [void] $dtMessageTracking.Rows.Add($row)
            }
            catch { 
                Write-Host $Global:Error[0].Exception.Message 
                $Global:Error[0].Exception.Message | Set-StatusMessage
            }
        }

    # -------------------------------------
    # - - -  TREEVIEW  - - -

        $treMessageTracking.Items.Clear()
        $dtMessageTracking | Group-Object sender | Sort-Object count -Descending | ForEach-Object{
        
        #region Sender
            [System.Array] $dataGroups = $_.group | Where-Object EventId -eq 'Send'
            
            $node = [Windows.Controls.TreeViewItem]::new()
            $node.Header     = "[$($dataGroups.count)] $($_.Name)"
            $node.IsSelected = $false
            $node.FontWeight = "Bold"
            $node.Tag        = "Sender;$($_.Name)"
           
            $treMessageTracking.Items.Add($node) | Out-Null
        #endregion

        #region Recipients
            [System.Array] $recipientsGroups = $dataGroups | Where-Object EventId -eq 'Send' | Group-Object Recipients
            
            foreach($group in $recipientsGroups)
            {
                $childNode = [Windows.Controls.TreeViewItem]::new()
                    $childNode.Header     = "[$($group.count)] $($group.Name)"                    
                    $childNode.FontWeight = "Normal"
                    $childNode.Tag        = "Recipients;$($group.Name)"
                    $node.Items.Add($childNode) | Out-Null
            }
            
        #endregion
        }

        # Refresh GUI
            $MainForm.Dispatcher.Invoke([System.Action]{},'Background')      
         
        # Remove existing PS sessions
            Get-PSSession | Where-Object { ($selectedExServer -match $_.ComputerName) -and ($_.State -eq 'Opened') -and ($_.ConfigurationName -eq 'Microsoft.Exchange') } | 
            Remove-PSSession -ErrorAction SilentlyContinue

        Write-Host "OK - Tracking" -ForegroundColor Green
        Write-Host''
        
    
    $('Finish - Message tracking - Entrys : ' + $($dgMessageTracking.Items.Count)) | Set-StatusMessage

    
    Write-Host '  F I N I S H E D  ' -BackgroundColor Green -ForegroundColor Black
    
    #endregion

}
