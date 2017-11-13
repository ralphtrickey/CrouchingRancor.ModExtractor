[CmdletBinding()]
Param(
    [string]$url
)

$m = [regex]::Match($url, "^https:\/\/swgoh\.gg\/u\/\w+\/")

if (-not $m.Success) {
    Throw "$url is not a valid swgoh.gg user URL"
}

$url = $m.Groups[0].Value + "mods/"

$slotMap = "","square","arrow","diamond","triangle","circle","cross"


# Stop execution on error
$ErrorActionPreference = "Stop"

function Resolve-ModSetName([string]$modname){
    if ($modname.Contains("Health")){
        return "health";
    }
    elseif ($modname.Contains("Offense")){
        return "offense";
    }
    elseif ($modname.Contains("Defense")){
        return "defense";
    }
    elseif ($modname.Contains("Speed")){
        return "speed";
    }
    elseif ($modname.Contains("Crit Chance")){
        return "critchance";
    }
    elseif ($modname.Contains("Crit Damage")){
        return "critdamage";
    }
    elseif ($modname.Contains("Potency")){
        return "potency";
    }
    elseif ($modname.Contains("Tenacity")){
        return "tenacity";
    }
}

function Get-ComTypeName($o)
{
    $typeGuid = $o.pstypenames[0].Split('#')[1]
    return (Get-ItemProperty "HKLM:\SOFTWARE\Classes\Interface\$typeGuid").'(default)'
}

function Scrape-ModPage([string]$url) {
    $mods = @();
    $r = Invoke-WebRequest $url
    
    $rows = $r.ParsedHtml.GetElementsByTagName("div") | ? { $_.className -eq "collection-mod" } 
    
    foreach ($row in $rows) {
    
        $mod = @{}
    
        $mod["mod_uid"] = $row.attributes["data-id"].textContent
        
        $slotID = [Int][regex]::Match($row.children[0].className, "pc-statmod-slot(\d+)").Groups[1].Value
        $mod["slot"] = $slotMap[$slotID]
    
        $modname = $row.getElementsByClassName("statmod-img")[0].alt
        $mod["set"] = Resolve-ModSetName $modname
        
        $mod["pips"] = $row.getElementsByClassName("statmod-pip").Length.ToString()
        $mod["level"] = $row.getElementsByClassName("statmod-level")[0].textContent
        $mod["characterName"] = $row.getElementsByClassName("char-portrait")[0].title
    
        $primarystats = $row.getElementsByClassName("statmod-stats-1")[0] | select -First 1

        if ($mods.Length -eq 0){
            #Write-Verbose $row.outerHTML
            Write-Verbose "row type: $(Get-ComTypeName $row)"
            Write-Verbose "primarystats type: $(Get-ComTypeName $primarystats)"
        }

        $mod["primaryBonusType"] = $primarystats.getElementsByClassName("statmod-stat-label")[0].textContent
        $mod["primaryBonusValue"] = $primarystats.getElementsByClassName("statmod-stat-value")[0].textContent
    

        # Make sure each mod object has all secondary attributes.. even if their not set
        foreach($i in 1..4){
            $mod["secondaryType_$($i)"] = ""
            $mod["secondaryValue_$($i)"] = ""
        }

        $secondarystatlist = $row.getElementsByClassName("statmod-stats-2")[0] | select -First 1

        if ($mods.Length -eq 0){
            Write-Verbose "secondary stat list type: $(Get-ComTypeName $secondarystatlist)"
        }

        $secondarystats = $secondarystatlist.getElementsByClassName("statmod-stat")
        for ($i = 0; $i -lt $secondarystats.length; $i++) {

            $stat = $secondarystats[$i] | select -First 1
            if (($mods.Length -eq 0) -and ($i -eq 0)){
                Write-Verbose "secondary stat type: $(Get-ComTypeName $stat)"
            }

            Write-Verbose "Setting secondaryType_$($i+1)"
            $mod["secondaryType_$($i+1)"] = $stat.getElementsByClassName("statmod-stat-label")[0].textContent
            
            Write-Verbose "Setting secondaryValue_$($i+1)"
            $mod["secondaryValue_$($i+1)"] = $stat.getElementsByClassName("statmod-stat-value")[0].textContent
        }
        
        Write-Verbose ($mod | ConvertTo-Json)
        $mods += $mod
    }

    # Get next page Url or quit...
    # <ul class='pagination'>
    #   <li>..<li>
    #   <li><a href="nexturl"></a><li>          <--------
    # </ul>
    Write-Verbose "Parsing pagination..."
    $pgr = $r.ParsedHtml.GetElementsByTagName("ul") | ? { $_.className.Contains("pagination") } | select -First 1

    Write-Verbose "Parsing pagination... step 2"
    $j = $pgr.children.length - 1

    Write-Verbose "Parsing pagination... step 3"
    $nexturl = [string]$pgr.children[$j].children[0].attributes["href"].textContent

    Write-Verbose "Next URL: $nexturl"
    if ($nexturl.StartsWith("/u/")){
        $mods += Scrape-ModPage "https://swgoh.gg$($nexturl)"
    }

    Write-Verbose "Returning mods: $($mods.Length)"
    return $mods
}

$mods = Scrape-ModPage $url 
$mods | ConvertTo-Json | Set-Content -Encoding UTF8 -Path "$($PSScriptRoot)\mods.json"