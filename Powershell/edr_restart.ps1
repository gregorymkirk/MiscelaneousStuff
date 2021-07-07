#EDR_restart.ps1
Param (
    [Parameter(Mandatory = $True)][ValidateSet("govpre","govprod")][string]$Environment,
    [Parameter(Mandatory = $True)][ValidateSet("ActiveResponse","EDS","Heimdall","Heimdall-Runtime")][String]$Service
)
. ./kubectl_functions.ps1


Function Main {
    Param (
    [Parameter(Mandatory = $True)][string]$Environment,
    [Parameter(Mandatory = $True)][String]$Service
    )
        Switch ($Service)
    {
        "ActiveResponse" { ActiveResponse -Environment $Environment }
        "EDS" { EDS -Environment $Environment }
        "Heimdall" { Heimdall -Enviroment $Environment }
        "Heimdall-Runtime" { Heimdall-Runtime -Enviroment $Environment }

    }

}

Function ActiveResponse {
    param ([string]$Environment)
    $Svc="mar"
    $Namespace = $Environment + $Svc
    $LogFile = "$Namespace.Log"
    
    write-host "env: $Environment"
    Write-host "NS: $NameSpace"
    
    "Runtime: $(get-date)"|tee-object -FilePath $LogFile 
    "Status at start:"|tee-object -FilePath $LogFile -Append
    kubectl -n $Namespace get pods |tee-object -FilePath $LogFile -Append
    
    #restart esearch database pods in sequence 
    PodRestartSequential -Label "app=database" -Namespace $NameSpace -Logfile $Logfile

    #Restart Search,Historical, Active Response, Remediation
    $Labels =@("app=mar-service-search", "app=mar-service-remediation", "app=mar-service-historical", "app=mar-service-active-response")

    foreach ($Label in $Labels){
        PodRestartSimultaneous -Label $Label -Namespace $NameSpace -Logfile $Logfile 
    }
}


Function EDS {
    param ([string]$Environment)
    $Svc="eds"
    $Namespace = $Environment + $Svc
    $LogFile = "$Namespace.Log"
    
    write-host "env: $Environment"
    Write-host "NS: $NameSpace"
    "Runtime: $(get-date)"|tee-object -FilePath $LogFile 
    "Status at start:"|tee-object -FilePath $LogFile -Append
    kubectl -n $Namespace get pods |tee-object -FilePath $LogFile -Append
    
    #Restart Zookeeper, Kafka
    $Labels =@("app=zk", "app=kfk" )
    foreach ($Label in $Labels){
        PodRestartSimultaneous -Label $Label -Namespace $NameSpace -Logfile $Logfile 
    }

    #Restart etcd pods in sequence 
    PodRestartSequential -Label "app=etcd" -Namespace $NameSpace -Logfile $Logfile

    #Restart Core an Query webservers
    $Labels =@("app=corews", "app=queryws" )
    foreach ($Label in $Labels){
        PodRestartSimultaneous -Label $Label -Namespace $NameSpace -Logfile $Logfile 
    }
}

Function Heimdall {
    param ([string]$Environment)
    $Namespace = "$($environment)heimdall"
    $LogFile = "$Namespace.Log"
    "Runtime: $(get-date)"|tee-object -FilePath $LogFile 
    "Status at start:"|tee-object -FilePath $LogFile -Append
    kubectl -n $Namespace get pods |tee-object -FilePath $LogFile -Append

    #Restart Services
    $Labels =@("app=heimdall", "app=heimdallbox", "app=heimdall-router")

    foreach ($Label in $Labels){
        PodRestartSimultaneous -Label $Label -Namespace $NameSpace -Logfile $Logfile 
    }
}





Main -Environment $Environment -Service $Service
