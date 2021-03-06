$githubAuthToken = $Env:githubAuthToken
$githubRepository = $Env:GITHUB_REPOSITORY
$refName = $Env:GITHUB_REF
$branchName = $refName.Replace("refs/heads/", "")
#$branchName = $Env:branch
$workspace = $Env:GITHUB_WORKSPACE + "\"
$sourceControlId = $Env:sourceControlId 
$csvPath = ".github\workflows\.sentinel\tracking_table_$sourceControlId.csv"
$global:localCsvTablefinal = @{}

$header = @{
    "authorization" = "Bearer $githubAuthToken"
}

#Writes sha dictionary object to csv file. Will delete any pre-existing content before writing.  
function WriteTableToCsv($shaTable) {
    if (Test-Path $csvPath) {
        Clear-Content -Path $csvPath
    }  
    Add-Content -Path $csvPath -Value "FileName, CommitSha"
    $shaTable.GetEnumerator() | ForEach-Object {
        "{0},{1}" -f $_.Key, $_.Value | add-content -path $csvPath
    }
}

#Converts hashtable to string that can be set as content when pushing csv file
function ConvertTableToString {
    $output = "FileName, CommitSha`n"
    $global:localCsvTablefinal.GetEnumerator() | ForEach-Object {
        $output += "{0},{1}`n" -f $_.Key, $_.Value
    }
    return $output
}

#Gets all files and commit shas using Get Trees API 
function GetGithubTree {
    # $branchResponse = Invoke-RestMethod https://api.github.com/repos/$githubRepository/branches/$branchName -Headers $header
    $branchResponse = AttemptInvokeRestMethod "Get" "https://api.github.com/repos/$githubRepository/branches/$branchName" $null $null 3
    $treeUrl = "https://api.github.com/repos/$githubRepository/git/trees/" + $branchResponse.commit.sha + "?recursive=true"
    # $getTreeResponse = Invoke-RestMethod $treeUrl -Headers $header
    $getTreeResponse = AttemptInvokeRestMethod "Get" $treeUrl $null $null 3
    return $getTreeResponse
}

#Gets blob commit sha of the csv file, used when updating csv file to repo 
function GetCsvCommitSha($getTreeResponse) {
    $shaObject = $getTreeResponse.tree |  Where-Object { $_.path -eq ".github/workflows/.sentinel/tracking_table_$sourceControlId.csv" }
    return $shaObject.sha
}

#Creates a table using the reponse from the tree api, creates a table 
function GetCommitShaTable($getTreeResponse) {
    $shaTable = @{}
    $getTreeResponse.tree | ForEach-Object {
        if ([System.IO.Path]::GetExtension($_.path) -eq ".json")
        {
            $truePath =  $_.path.Replace("/", "\")
            $shaTable.Add($truePath, $_.sha)
            Write-Output $truePath
            Write-Output $_.sha
        }
    }
    #Write-Output $shaTable
    return $shaTable
}

#Pushes new/updated csv file to the user's repository. If updating file, will need csv commit sha. 
#TODO: Add source control id to tracking_table name.
function PushCsvToRepo($getTreeResponse) {
    $path = ".github/workflows/.sentinel/tracking_table_$sourceControlId.csv"
    Write-Output $path
    $sha = GetCsvCommitSha $getTreeResponse
    #$sha = "70c379b63ffa0795fdbfbc128e5a2818397b7ef8"
    $createFileUrl = "https://api.github.com/repos/$githubRepository/contents/$path"
    $content = ConvertTableToString
    $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
    # $encodedContent = "SGVsbG8gd29ybGQgbmV3"
    Write-Output $encodedContent
    $body = @{
        message = "trackingTable.csv created."
        content = $encodedContent
        branch = $branchName
        sha = $sha
    } | ConvertTo-Json

    $Parameters = @{
        Method      = "PUT"
        Uri         = $createFileUrl
        Headers     = $header
        Body        = $body | ConvertTo-Json
    }
    Write-Output $Parameters | Out-String
    # Invoke-RestMethod @Parameters
    AttemptInvokeRestMethod "Put" $createFileUrl $body $null 3
}

function main {
    Write-Output $githubRepository
    $tree = GetGithubTree
    $shaTable = GetCommitShaTable $tree 
    $global:localCsvTablefinal = $shaTable
    PushCsvToRepo $tree
    Write-Output "SHA TABLE"
    Write-Output $shaTable
}

function AttemptInvokeRestMethod($method, $url, $body, $contentTypes, $maxRetries) {
    $Stoploop = $false
    $retryCount = 0
    do {
        try {
            $result = Invoke-RestMethod -Uri $url -Method $method -Headers $header -Body $body -ContentType $contentTypes
            $Stoploop = $true
        }
        catch {
            if ($retryCount -gt $maxRetries) {
                Write-Host "[Error] API call failed after $retryCount retries: $_"
                $Stoploop = $true
            }
            else {
                Write-Host "[Warning] API call failed: $_.`n Conducting retry #$retryCount."
                Start-Sleep -Seconds 5
                $retryCount = $retryCount + 1
            }
        }
    }
    While ($Stoploop -eq $false)
    return $result
}

main
# $shaTable = @{}
# $tree = GetGithubTree 
# Write-Output $tree
# $sha = GetCsvCommitSha $tree
# Write-Output $sha
# $shaTable = GetCommitShaTable $tree
# Write-Output $shaTable
# $sha = GetCsvCommitSha $tree
# Write-Output $sha

