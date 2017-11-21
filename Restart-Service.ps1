param  
   (  
    [Parameter (Mandatory=$true)]  
    [object] $WebhookData  
   )

#login to Azure:
$Conn = Get-AutomationConnection -Name AzureRunAsConnection
Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID `
-ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

#Extract data from webhook
$SearchResults = (ConvertFrom-Json $WebhookData.RequestBody).SearchResults.value
$serviceName = $SearchResults.ServiceName_CF
write-verbose = "Service Name: $serviceName"
$computerName = $SearchResults.Computer
write-verbose = "Computer Name: $computerName"

foreach ($computer in $computerName){
    #Get Server FQDN
    $vmResource = Find-AzureRmResource -ResourceNameContains $computer -ResourceType "Microsoft.Compute/virtualMachines"
    $vm = Get-AzureRMVM -ResourceGroupName $vmResource.ResourceGroupName -Name $vmResource.Name
    Write-Output "VM located: $($vm.Name)"
    $vm.NetworkProfile
    $vm.NetworkProfile.NetworkInterfaces.Id
    $nicRef = Get-AzureRMResource -ResourceId $vm.NetworkProfile.NetworkInterfaces.Id
    $nic = Get-AzureRmNetworkInterface -Name $nicRef.Name -ResourceGroupName $nicRef.ResourceGroupName
    $publicIpRef = Get-AzureRmResource -ResourceId $nic.IpConfigurations.PublicIpAddress.Id
    $publicIp = Get-AzureRmPublicIpAddress -Name $publicIpRef.Name -ResourceGroupName $publicIpRef.ResourceGroupName
    $fqdn = $publicIp.DnsSettings.Fqdn
    Write-Output "Connecting to VM: $($fqdn)"

    #set the winrm port
    $winrmPort = "5986"
    # Get the credentials of the machine
    $cred = Get-AutomationPSCredential -Name 'aa-admin'

    # Connect to the machine
    $soptions = New-PSSessionOption -SkipCACheck          
    Invoke-Command -ComputerName $fqdn -Credential $cred -Port $winrmPort -UseSSL -SessionOption $soptions -Debug -ScriptBlock {
        param($serviceDisplayName)
        $service = Get-Service -DisplayName $serviceDisplayName
        #if service isnt running, start it
        write-verbose = "Service Status: $service.Status"
        if ($service.Status -ne "Running"){            
            $service | Start-Service 
        }
    } -ArgumentList $serviceName
}