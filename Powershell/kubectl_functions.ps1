#Kubernetes Control Functions
#Depends on Kubctl working ion the server where these run
#We may look at improving these via Direct API calls in the future

function PodsByLabel{
    Param( 
        [Parameter(Mandatory=$true)][String]$Label,
        [Parameter(Mandatory=$true)][String]$NameSpace
    )
    
    $pods = $pods = kubectl -n $namespace get pods -l $label -o json |out-string|convertfrom-json
    return $pods
}

Function PodUp {
    #Acccepts and object from the output of PodsBylabel and check to see if all pods have reached a ready status
    #Returns $True once all container statuses are Ready. 
    #will check to see if the containers are up for up to 5 minutes before returning $False
    Param( 
        [Parameter(Mandatory=$true)][String]$PodName,
        [Parameter(Mandatory=$true)][String]$NameSpace,
        [Int32]$WaitTime = 5 #in Minutes
    )
    $Pod = kubectl -n $namespace get pod $PodName -o json |out-string|convertfrom-json
    $count = $pod.status.containerstatuses.count
    $good = 0
    While ($good -lt $count){
        $good=0
        $Pod = kubectl -n $namespace get pod $PodName -o json |out-string|convertfrom-json
        foreach ($status in $pod.status.containerstatuses) {
            if ($status.ready) {$good +=1}
        }
        $iterations ++
        write-host $iterations
        if ($iterations -gt ($WaitTime * 4)) {Return $False}
        start-sleep -Seconds 15
    }
    Return $true
}

Function PodRestartSequential {
    Param( 
        [Parameter(Mandatory=$true)][String]$Label,
        [Parameter(Mandatory=$true)][String]$NameSpace,
        [Parameter(Mandatory=$true)][String]$LogFile,
        [Int32]$WaitTime = 5 #Time to Wait for each Pod to come up in minutes
    )
    $Pods = PodsByLabel -Label $Label -Namespace $NameSpace
    foreach ($Pod in $Pods.Items) {
        kubectl -n $NameSpace delete pod $Pod.metadata.name
        start-sleep -Seconds 30
        if ($(PodUp -NameSpace $NameSpace -Podname $Pod.metadata.name -WaitTime $WaitTime )){
            kubectl -n $NameSpace get pod $Pod.metadata.name |tee-object -FilePath $Logfile -Append
            write-host "Pod $($Pod.metadata.name) is Ready"
        }
        else{
            kubectl -n $NameSpace get pod $Pod.metadata.name |tee-object -FilePath $Logfile -Append
            throw "Pod $($Pod.metadata.name) is not coming up, exiting with error" |tee-object -FilePath $LogFile -Append
        }
    }
}

Function PodRestartSimultaneous {
    Param(
        [Parameter(Mandatory=$true)][String]$Label,
        [Parameter(Mandatory=$true)][String]$NameSpace,
        [Parameter(Mandatory=$true)][String]$LogFile,
        [Int32]$WaitTime = 5 #Time to Wait for each Pod to come up in minutes
    )
    $Deployments = ( kubectl -n $NameSpace get deployment -o json ) |out-string|convertfrom-json
    $ltag = $label.split("=")[0]
    $lvalue = $label.split("=")[1]
    $replicas = $($Deployments.Items|where-object{$_.spec.selector.matchlabels.$ltag -eq $lvalue}).spec.replicas
    kubectl -n $NameSpace delete pod -l $label 
    $GoodReplicas = 0
    while ($GoodReplicas -lt $replicas){
        $GoodReplicas = 0
        start-sleep -Seconds 15
        $Pods = PodsByLabel -Label $label -Namespace $NameSpace
        foreach ($Pod in $Pods.items) {
            if (PodUp -NameSpace $Namespace -WaitTime $WaitTime -PodName $Pod.metadata.name) {
                $GoodReplicas ++
            }
        }
    }
}
