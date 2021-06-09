#Post Patch Review

Main {
    initialize-AWSDefaults -ProfileName "prod" -region us-gov-west-1
    OutputReview -CommandId "574dac46-069c-4f0e-9985-986d21957da1"
}


Function OutputReview {
    Param(
        [Parameter(Mandatory=$True)]$CommandId
    )
    $J = Get-ssmCommandInvocation -CommandId $CommandID

    forEACH ($I in $J) {
        $detail = Get-SSMCommandInvocationDetail -CommandID $I.commandID -InstanceId $I.InstanceId
        "$($detail.InstanceID)"|Tee-Object -Filepath .\outfile.txt -Append
        "$($detail.StandardOutputContent)"|Tee-Object -Filepath .\outfile.txt -Append
    }
}

Main