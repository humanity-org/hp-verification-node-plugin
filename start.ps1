#Requires -Version 5.1
<#
.SYNOPSIS
    Humanity Protocol - Verification Node Setup Wizard (Windows)
.DESCRIPTION
    Interactive setup script for HP Verification Node Plugin.
    Mirrors the full functionality of start.sh for Windows users.
.EXAMPLE
    .\start.ps1
    .\start.ps1 --owner-address 0x1234...abcd
    .\start.ps1 --restart -v
    & ([scriptblock]::Create((irm <url>))) --network mainnet
#>
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ScriptArgs
)

# NOTE: Do NOT use $ErrorActionPreference = "Stop" globally.
# Docker and other external commands write to stderr for warnings/progress,
# which PowerShell's "Stop" mode treats as terminating errors, killing the script.
$ErrorActionPreference = "Continue"

# ─────────────────────────────────────────
# Constants
# ─────────────────────────────────────────
$HP_NODE_DIR = Join-Path $env:USERPROFILE "hp-node"
$CONFIG_DIR = Join-Path $HP_NODE_DIR "configs"

# Network selection (set via --network flag, default: testnet)
$NETWORK = "testnet"

function Set-NetworkConfig {
    switch ($script:NETWORK) {
        "mainnet" {
            $script:IMAGE_NAME = "ghcr.io/humanity-org/hp-verification-node-plugin:latest"
            $script:RPC_URL = "https://humanity-mainnet.g.alchemy.com/public"
            $script:DELEGATION_HUB = "0x2cD43813903c48E0BDb6699E992eB8216dCEf48D"
            $script:LICENSE_NFT = "0x7a888bF4ec4FA9653B79B089736647024Ff0Aa30"
        }
        default {
            $script:IMAGE_NAME = "ghcr.io/humanity-org/hp-verification-node-plugin:testnet"
            $script:RPC_URL = "https://humanity-testnet.g.alchemy.com/public"
            $script:DELEGATION_HUB = "0x1aEbB36b9A6B33E377319a7E2d928BE54d0cB68e"
            $script:LICENSE_NFT = "0xF04f1062D70432d167EB9f342b98063228c6b496"
        }
    }
}
$SEL_GET_INCOMING_DELEGATIONS = "0xe2ae2879"
$SEL_GET_INCOMING_DELEGATION_OFFERS = "0x49ceece3"
$SEL_OWNER_OF = "0x6352211e"
$POLL_INTERVAL = 10

# ─────────────────────────────────────────
# Parse CLI arguments
# ─────────────────────────────────────────
$ARG_OWNER = ""
$ARG_KEY = ""
$ARG_NAME = ""
$VERBOSE = $false
$LOG_LEVEL = "info"
$RESTART = $false
$FORCE_NEW_WALLET = $false

function Show-Help {
    Write-Host "Usage: start.cmd [options]"
    Write-Host ""
    Write-Host "  Running without options starts the interactive setup wizard."
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --owner-address <address>      License NFT holder's Ethereum address"
    Write-Host "  --private-key <private_key>    Private key for transaction signing"
    Write-Host "  --container-name <name>        Custom container name (default: hp-verification-node-plugin)"
    Write-Host "  --network <testnet|mainnet>    Select network (default: testnet)"
    Write-Host "  --restart                      Restart using saved config (skip wizard)"
    Write-Host "  -v, --verbose                  Enable debug-level logging"
    Write-Host "  -h, --help, /?                 Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  start.cmd                                                    # Full interactive wizard"
    Write-Host "  start.cmd --restart                                          # Restart with saved config"
    Write-Host "  start.cmd --restart --container-name my-node                 # Restart a specific node"
    Write-Host "  start.cmd --owner-address 0x1234...abcd                      # Skip owner address step"
    Write-Host "  start.cmd --owner-address 0x1234... --private-key abcd1234..."
    Write-Host "  set OWNER_ADDRESS=0x1234... & start.cmd"
    exit 0
}

$i = 0
while ($i -lt $ScriptArgs.Count) {
    switch ($ScriptArgs[$i]) {
        { $_ -in "-h", "--help", "/?" } { Show-Help }
        { $_ -in "-v", "--verbose" } { $script:VERBOSE = $true; $script:LOG_LEVEL = "debug"; $i++ }
        "--restart" { $script:RESTART = $true; $i++ }
        "--owner-address" {
            if ($i + 1 -ge $ScriptArgs.Count) { Write-Host "Error: --owner-address requires a value."; exit 1 }
            $script:ARG_OWNER = $ScriptArgs[$i + 1]; $i += 2
        }
        "--private-key" {
            if ($i + 1 -ge $ScriptArgs.Count) { Write-Host "Error: --private-key requires a value."; exit 1 }
            $script:ARG_KEY = $ScriptArgs[$i + 1]; $i += 2
        }
        "--container-name" {
            if ($i + 1 -ge $ScriptArgs.Count) { Write-Host "Error: --container-name requires a value."; exit 1 }
            $script:ARG_NAME = $ScriptArgs[$i + 1]; $i += 2
        }
        "--network" {
            if ($i + 1 -ge $ScriptArgs.Count) { Write-Host "Error: --network requires a value (testnet or mainnet)."; exit 1 }
            $script:NETWORK = $ScriptArgs[$i + 1]; $i += 2
        }
        default {
            Write-Host "Unknown option: $($ScriptArgs[$i])"
            Write-Host "Run 'start.cmd --help' for usage."
            exit 1
        }
    }
}

# Apply network configuration based on --network flag
Set-NetworkConfig

# ─────────────────────────────────────────
# Print helpers (colored output)
# ─────────────────────────────────────────
function Print-Banner {
    Write-Host ""
    Write-Host "  =========================================" -ForegroundColor Cyan
    Write-Host "    Humanity Protocol - Node Setup Wizard   " -ForegroundColor Cyan
    Write-Host "  =========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Print-Step {
    param([int]$Step, [int]$Total, [string]$Title, [bool]$ShowBack = $true)
    Write-Host ""
    Write-Host "  [Step $Step/$Total] $Title" -ForegroundColor Green
    Write-Host "  -----------------------------------------" -ForegroundColor DarkGray
    if ($ShowBack -and $Step -gt 1 -and $Step -le $Total) {
        Write-Host "  Type 'b' to go back to the previous step." -ForegroundColor DarkGray
    }
}

function Print-Info { param([string]$Msg); Write-Host "  i  $Msg" -ForegroundColor Cyan }
function Print-Warn { param([string]$Msg); Write-Host "  !  $Msg" -ForegroundColor Yellow }
function Print-Error { param([string]$Msg); Write-Host "  x  $Msg" -ForegroundColor Red }
function Print-Success { param([string]$Msg); Write-Host "  +  $Msg" -ForegroundColor Green }

# ─────────────────────────────────────────
# Validation helpers
# ─────────────────────────────────────────
function Test-EthAddress {
    param([string]$Addr)
    return $Addr -match "^0x[0-9a-fA-F]{40}$"
}

function Test-PrivateKey {
    param([string]$Key)
    return $Key -match "^[0-9a-fA-F]{64}$"
}

function Strip-0xPrefix {
    param([string]$Val)
    if ($Val -match "^0[xX]") { return $Val.Substring(2) }
    return $Val
}

# ─────────────────────────────────────────
# Config save/load
# ─────────────────────────────────────────
function Save-Config {
    if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }
    $configFile = Join-Path $CONFIG_DIR "$CONTAINER_NAME.conf"
    @(
        "# HP Verification Node configuration (auto-generated)"
        "# Container: $CONTAINER_NAME"
        "OWNER_ADDRESS=$OWNER_ADDRESS"
        "CONTAINER_NAME=$CONTAINER_NAME"
        "HAS_CUSTOM_KEY=$HAS_CUSTOM_KEY"
        "ETH_PRIVATE_KEY=$ETH_PRIVATE_KEY"
        "LOG_LEVEL=$LOG_LEVEL"
    ) | Set-Content -Path $configFile -Encoding UTF8
    # Restrict permissions: remove inheritance, grant only current user
    $null = & icacls $configFile /inheritance:r /grant:r "$($env:USERNAME):F" 2>&1
}

function Load-Config {
    param([string]$Name)
    $configFile = Join-Path $CONFIG_DIR "$Name.conf"
    if (-not (Test-Path $configFile)) { return $false }
    Get-Content $configFile | ForEach-Object {
        if ($_ -match "^([A-Z_]+)=(.*)$") {
            Set-Variable -Name $Matches[1] -Value $Matches[2] -Scope Script
        }
    }
    return $true
}

function Get-ConfigList {
    if (-not (Test-Path $CONFIG_DIR)) { return @() }
    return @(Get-ChildItem -Path $CONFIG_DIR -Filter "*.conf" -File)
}

# ─────────────────────────────────────────
# RPC helpers (Invoke-RestMethod)
# ─────────────────────────────────────────
function Invoke-RpcCall {
    param([string]$Payload)
    try {
        $response = Invoke-RestMethod -Uri $RPC_URL -Method Post -ContentType "application/json" -Body $Payload -TimeoutSec 10 -ErrorAction Stop
        return $response.result
    }
    catch { return $null }
}

function Test-GasFunded {
    param([string]$Address)
    $payload = @{ jsonrpc = "2.0"; method = "eth_getBalance"; params = @($Address, "latest"); id = 1 } | ConvertTo-Json
    $result = Invoke-RpcCall $payload
    if (-not $result -or $result -eq "0x0" -or $result -eq "0x") {
        return @{ Funded = $false; Hex = $result; Display = "0 HP" }
    }
    $display = Convert-HexToBalance $result
    return @{ Funded = $true; Hex = $result; Display = $display }
}

function Convert-HexToBalance {
    param([string]$Hex)
    $hex = $Hex -replace "^0x", ""
    if (-not $hex -or $hex -eq "0") { return "0 HP" }
    try {
        $dec = [System.Numerics.BigInteger]::Parse("0" + $hex, [System.Globalization.NumberStyles]::HexNumber)
        $divisor = [System.Numerics.BigInteger]::Parse("1000000000000000")  # 10^15 for 3 decimal places
        $scaled = [System.Numerics.BigInteger]::Divide($dec, $divisor)
        $intPart = [System.Numerics.BigInteger]::Divide($scaled, 1000)
        $fracPart = [System.Numerics.BigInteger]::Remainder($scaled, 1000)
        if ($intPart -eq 0 -and $fracPart -eq 0) { return "< 0.001 HP" }
        return "$intPart.$($fracPart.ToString().PadLeft(3, '0')) HP"
    }
    catch { return "? HP" }
}

function Invoke-EthCall {
    param([string]$To, [string]$Data)
    $payload = @{ jsonrpc = "2.0"; method = "eth_call"; params = @(@{ to = $To; data = $Data }, "latest"); id = 1 } | ConvertTo-Json -Depth 3
    $result = Invoke-RpcCall $payload
    if ($result) { return $result -replace "^0x", "" }
    return ""
}

function Pad-Address {
    param([string]$Addr)
    $hex = ($Addr -replace "^0x", "").ToLower()
    return $hex.PadLeft(64, '0')
}

function Test-Delegation {
    param([string]$BurnerAddress, [string]$OwnerAddress)
    $ownerLower = $OwnerAddress.ToLower()
    $paddedAddr = Pad-Address $BurnerAddress
    $paddedOffset = "0" * 64
    $paddedLimit = ("0" * 62) + "64"  # 100
    $calldata = "$SEL_GET_INCOMING_DELEGATIONS$paddedAddr$paddedOffset$paddedLimit"
    $hexResult = Invoke-EthCall $DELEGATION_HUB $calldata
    if (-not $hexResult -or $hexResult.Length -lt 128) { return $false }

    # Parse ABI-encoded Delegation[] response
    $arrayLenHex = $hexResult.Substring(64, 64)
    $arrayLen = [Convert]::ToInt64($arrayLenHex, 16)
    if ($arrayLen -eq 0) { return $false }

    # Each struct: 5 x 64 hex = 320 hex chars
    $structStart = 128
    $structSize = 320

    for ($j = 0; $j -lt $arrayLen; $j++) {
        $offset = $structStart + $j * $structSize
        if ($offset + $structSize -gt $hexResult.Length) { break }
        $dTokenId = $hexResult.Substring($offset + 128, 64)
        $dEnabled = $hexResult.Substring($offset + 256, 64)
        $enabledVal = [Convert]::ToInt64($dEnabled, 16)
        if ($enabledVal -ne 0) {
            $ownerCalldata = "$SEL_OWNER_OF$dTokenId"
            $ownerResult = Invoke-EthCall $LICENSE_NFT $ownerCalldata
            if ($ownerResult -and $ownerResult.Length -ge 64) {
                $nftOwner = "0x" + $ownerResult.Substring(24, 40)
                if ($nftOwner.ToLower() -eq $ownerLower) { return $true }
            }
        }
    }
    return $false
}

function Test-DelegationOffer {
    param([string]$BurnerAddress, [string]$OwnerAddress)
    $ownerLower = $OwnerAddress.ToLower()
    $paddedAddr = Pad-Address $BurnerAddress
    $paddedOffset = "0" * 64
    $paddedLimit = ("0" * 62) + "64"
    $calldata = "$SEL_GET_INCOMING_DELEGATION_OFFERS$paddedAddr$paddedOffset$paddedLimit"
    $hexResult = Invoke-EthCall $DELEGATION_HUB $calldata
    if (-not $hexResult -or $hexResult.Length -lt 128) { return $false }

    $arrayLenHex = $hexResult.Substring(64, 64)
    $arrayLen = [Convert]::ToInt64($arrayLenHex, 16)
    if ($arrayLen -eq 0) { return $false }

    # Each struct: 6 x 64 hex = 384 hex chars
    $structStart = 128
    $structSize = 384

    for ($j = 0; $j -lt $arrayLen; $j++) {
        $offset = $structStart + $j * $structSize
        if ($offset + $structSize -gt $hexResult.Length) { break }
        $dFrom = $hexResult.Substring($offset + 128, 64)
        $dEnabled = $hexResult.Substring($offset + 320, 64)
        $enabledVal = [Convert]::ToInt64($dEnabled, 16)
        if ($enabledVal -ne 0) {
            $offerFrom = "0x" + $dFrom.Substring(24, 40)
            if ($offerFrom.ToLower() -eq $ownerLower) { return $true }
        }
    }
    return $false
}

# ─────────────────────────────────────────
# Ethereum address derivation (pure .NET)
# ─────────────────────────────────────────

# Compile a minimal C# helper for secp256k1 + Keccak-256.
# This runs once per session and is cached by PowerShell.
if (-not ([System.Management.Automation.PSTypeName]'EthCrypto').Type) {
    Add-Type -Language CSharp -ReferencedAssemblies System.Numerics -TypeDefinition @'
using System;
using System.Numerics;

public static class EthCrypto
{
    // secp256k1 curve parameters
    static readonly BigInteger P  = BigInteger.Parse("0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", System.Globalization.NumberStyles.HexNumber);
    static readonly BigInteger N  = BigInteger.Parse("0FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", System.Globalization.NumberStyles.HexNumber);
    static readonly BigInteger Gx = BigInteger.Parse("079BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", System.Globalization.NumberStyles.HexNumber);
    static readonly BigInteger Gy = BigInteger.Parse("0483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", System.Globalization.NumberStyles.HexNumber);

    static BigInteger ModInverse(BigInteger a, BigInteger m)
    {
        BigInteger g, x, _; ExtGcd(a % m + m, m, out g, out x, out _);
        return (x % m + m) % m;
    }
    static void ExtGcd(BigInteger a, BigInteger b, out BigInteger g, out BigInteger x, out BigInteger y)
    {
        if (a == 0) { g = b; x = 0; y = 1; return; }
        BigInteger g1, x1, y1; ExtGcd(b % a, a, out g1, out x1, out y1);
        g = g1; x = y1 - (b / a) * x1; y = x1;
    }

    static void PointAdd(BigInteger x1, BigInteger y1, BigInteger x2, BigInteger y2, out BigInteger rx, out BigInteger ry)
    {
        if (x1 == 0 && y1 == 0) { rx = x2; ry = y2; return; }
        if (x2 == 0 && y2 == 0) { rx = x1; ry = y1; return; }
        if (x1 == x2 && y1 != y2) { rx = 0; ry = 0; return; } // inverse points → infinity
        BigInteger lam;
        if (x1 == x2 && y1 == y2)
            lam = (3 * x1 * x1) % P * ModInverse(2 * y1, P) % P;
        else
            lam = (y2 - y1 + P * 4) % P * ModInverse((x2 - x1 + P * 4) % P, P) % P;
        rx = (lam * lam - x1 - x2 + P * 4) % P;
        ry = (lam * (x1 - rx + P * 2) - y1 + P * 2) % P;
    }

    static void ScalarMul(BigInteger k, BigInteger bx, BigInteger by, out BigInteger rx, out BigInteger ry)
    {
        rx = 0; ry = 0;
        BigInteger cx = bx, cy = by;
        while (k > 0)
        {
            if (!k.IsEven) PointAdd(rx, ry, cx, cy, out rx, out ry);
            PointAdd(cx, cy, cx, cy, out cx, out cy);
            k >>= 1;
        }
    }

    public static byte[] GetPublicKey(byte[] privKey)
    {
        // privKey is 32 bytes big-endian
        byte[] padded = new byte[privKey.Length + 1];
        Array.Copy(privKey, 0, padded, 1, privKey.Length);
        Array.Reverse(padded); // little-endian for BigInteger
        BigInteger k = new BigInteger(padded);
        if (k <= 0 || k >= N) return null;

        BigInteger rx, ry;
        ScalarMul(k, Gx, Gy, out rx, out ry);

        // Output 64 bytes: x(32) || y(32), big-endian
        byte[] xb = rx.ToByteArray(), yb = ry.ToByteArray();
        byte[] pub = new byte[64];
        // Copy in big-endian, right-aligned
        for (int i = 0; i < Math.Min(xb.Length, 32); i++) pub[31 - i] = xb[i];
        for (int i = 0; i < Math.Min(yb.Length, 32); i++) pub[63 - i] = yb[i];
        return pub;
    }

    // ---- Keccak-256 ----
    static readonly ulong[] RC = {
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    };
    static readonly int[] Rot = {
        1,3,6,10,15,21,28,36,45,55,2,14,27,41,56,8,25,43,62,18,39,61,20,44
    };
    static readonly int[] PiLane = {
        10,7,11,17,18,3,5,16,8,21,24,4,15,23,19,13,12,2,20,14,22,9,6,1
    };

    public static byte[] Keccak256(byte[] data)
    {
        int rate = 136; // (1600-256*2)/8
        // Pad
        int q = rate - (data.Length % rate);
        byte[] padded = new byte[data.Length + q];
        Array.Copy(data, padded, data.Length);
        padded[data.Length] = 0x01;
        padded[padded.Length - 1] |= 0x80;

        ulong[] state = new ulong[25];
        for (int off = 0; off < padded.Length; off += rate)
        {
            for (int i = 0; i < rate / 8; i++)
                state[i] ^= BitConverter.ToUInt64(padded, off + i * 8);
            KeccakF(state);
        }
        byte[] hash = new byte[32];
        for (int i = 0; i < 4; i++)
            Array.Copy(BitConverter.GetBytes(state[i]), 0, hash, i * 8, 8);
        return hash;
    }

    static ulong RotL(ulong x, int n) { return (x << n) | (x >> (64 - n)); }

    static void KeccakF(ulong[] st)
    {
        for (int round = 0; round < 24; round++)
        {
            // θ
            ulong[] C = new ulong[5];
            for (int x = 0; x < 5; x++) C[x] = st[x] ^ st[x + 5] ^ st[x + 10] ^ st[x + 15] ^ st[x + 20];
            for (int x = 0; x < 5; x++)
            {
                ulong d = C[(x + 4) % 5] ^ RotL(C[(x + 1) % 5], 1);
                for (int y = 0; y < 25; y += 5) st[y + x] ^= d;
            }
            // ρ + π
            ulong last = st[1];
            for (int i = 0; i < 24; i++)
            {
                int j = PiLane[i];
                ulong tmp = st[j]; st[j] = RotL(last, Rot[i]); last = tmp;
            }
            // χ
            for (int y = 0; y < 25; y += 5)
            {
                ulong[] t = { st[y], st[y + 1], st[y + 2], st[y + 3], st[y + 4] };
                for (int x = 0; x < 5; x++) st[y + x] = t[x] ^ (~t[(x + 1) % 5] & t[(x + 2) % 5]);
            }
            // ι
            st[0] ^= RC[round];
        }
    }

    /// <summary>Derive Ethereum address from 32-byte private key. Returns "0x..." or null.</summary>
    public static string DeriveAddress(byte[] privKey)
    {
        byte[] pub = GetPublicKey(privKey);
        if (pub == null) return null;
        byte[] hash = Keccak256(pub);
        // Last 20 bytes
        string addr = "0x";
        for (int i = 12; i < 32; i++) addr += hash[i].ToString("x2");
        return addr;
    }
}
'@
}

function Derive-EthAddress {
    param([string]$PrivKeyHex)
    try {
        $bytes = New-Object byte[] 32
        for ($i = 0; $i -lt 32; $i++) {
            $bytes[$i] = [Convert]::ToByte($PrivKeyHex.Substring($i * 2, 2), 16)
        }
        return [EthCrypto]::DeriveAddress($bytes)
    }
    catch {
        return $null
    }
}

# ─────────────────────────────────────────
# Wallet address helpers
# ─────────────────────────────────────────
function Get-BurnerAddress {
    $cacheFile = Join-Path $HP_NODE_DIR "data\$CONTAINER_NAME\flohive-cache.json"
    $maxAttempts = 15

    for ($attempt = 0; $attempt -lt $maxAttempts; $attempt++) {
        if (Test-Path $cacheFile) {
            try {
                $json = Get-Content $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $addr = $json.burnerWallet.address
                if ($addr -and $addr -ne "") {
                    Write-Host "`r                                        " -NoNewline
                    Write-Host "`r" -NoNewline
                    return $addr
                }
            }
            catch { }
        }
        $spinChars = @('|', '/', '-', '\')
        $spin = $spinChars[$attempt % 4]
        Write-Host "`r  $spin Generating wallet...  " -NoNewline -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }
    Write-Host "`r                                        " -NoNewline
    Write-Host "`r" -NoNewline

    # Fallback 1: docker logs
    try {
        $logs = (docker logs $CONTAINER_NAME 2>&1) -join "`n"
        $match = [regex]::Match($logs, 'Address: (0x[0-9a-fA-F]+)')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    catch { }

    # Fallback 2: derive from ETH_PRIVATE_KEY if set
    if ($script:ETH_PRIVATE_KEY) {
        $derived = Derive-EthAddress -PrivKeyHex $script:ETH_PRIVATE_KEY
        if ($derived) { return $derived }
    }

    return $null
}

function Write-WalletCache {
    param([string]$DataDir, [string]$PrivKeyHex)
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    $cacheFile = Join-Path $DataDir "flohive-cache.json"

    # Try to derive address from private key (same as start.sh)
    $derivedAddr = Derive-EthAddress -PrivKeyHex $PrivKeyHex
    if (-not $derivedAddr) { $derivedAddr = "" }

    $jsonContent = @{ burnerWallet = @{ privateKey = $PrivKeyHex; address = $derivedAddr } } | ConvertTo-Json -Compress
    # Write UTF-8 without BOM — PowerShell 5.1's -Encoding UTF8 adds a BOM that breaks Go's JSON parser
    [System.IO.File]::WriteAllText($cacheFile, $jsonContent, (New-Object System.Text.UTF8Encoding $false))
    return $derivedAddr
}

function Display-Wallet {
    param([string]$Address)
    Write-Host ""
    Write-Host "  ====================================================" -ForegroundColor Green
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host "  |  Your Node's Burner Wallet Address:              |" -ForegroundColor Green
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host -NoNewline "  |  " -ForegroundColor Green
    Write-Host -NoNewline $Address -ForegroundColor Cyan
    Write-Host "      |" -ForegroundColor Green
    Write-Host "  |                                                    |" -ForegroundColor Green
    Write-Host "  ====================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Almost there! Complete these 2 steps to activate your node:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Step A - Bind your License to this node:" -ForegroundColor White
    Write-Host "     1. Open " -NoNewline
    Write-Host "https://node.hptestingsite.com/licenses" -NoNewline -ForegroundColor Cyan
    Write-Host " in your browser"
    Write-Host "     2. Connect with your owner wallet (the one holding the License NFT)"
    Write-Host "     3. Bind the license to this node address: " -NoNewline
    Write-Host $Address -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Step B - Fund this node with gas:" -ForegroundColor White
    Write-Host "     Send a small amount of tokens to: " -NoNewline
    Write-Host $Address -ForegroundColor Cyan
    Write-Host "     (Your node needs gas to submit transactions on-chain)" -ForegroundColor DarkGray
    Write-Host "     To ensure your node operates continuously for 1 year without interruption," -ForegroundColor Yellow
    Write-Host "     we recommend depositing at least 5 HP." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  The script will automatically detect when both steps are done." -ForegroundColor DarkGray
    Write-Host ""
}

function Print-ManageInstructions {
    Write-Host ""
    Write-Host "  Useful commands:" -ForegroundColor White
    Write-Host "    See what your node is doing:  " -NoNewline
    Write-Host "docker logs -f $CONTAINER_NAME" -ForegroundColor Cyan
    Write-Host "    Stop your node:               " -NoNewline
    Write-Host "docker stop $CONTAINER_NAME" -ForegroundColor Cyan
    Write-Host "    Start/restart your node:      " -NoNewline
    Write-Host "start.cmd" -ForegroundColor Cyan
    Write-Host ""
}

# ─────────────────────────────────────────
# Polling loop
# ─────────────────────────────────────────
function Start-Polling {
    param([string]$BurnerAddress)

    $gasOk = $false
    $delegationOk = $false

    Write-Host "  Checking your setup status..." -ForegroundColor Cyan
    Write-Host "  (Press Ctrl+C to exit - your node keeps running either way)" -ForegroundColor DarkGray
    Write-Host ""

    try {
        while ($true) {
            # Save cursor position
            $cursorTop = [Console]::CursorTop

            # Check 1: Balance
            $balResult = Test-GasFunded $BurnerAddress
            if ($balResult.Funded) {
                $gasOk = $true
                Write-Host "  [+] Balance: $($balResult.Display)" -ForegroundColor Green
            }
            else {
                Write-Host "  [ ] Balance: 0 HP         - Send tokens to " -NoNewline -ForegroundColor DarkGray
                Write-Host $BurnerAddress -ForegroundColor Cyan
            }

            # Check 2: License binding
            if (-not $delegationOk) {
                if (Test-Delegation $BurnerAddress $OWNER_ADDRESS) {
                    $delegationOk = $true
                    $ownerShort = $OWNER_ADDRESS.Substring(0, 6) + "..." + $OWNER_ADDRESS.Substring($OWNER_ADDRESS.Length - 4)
                    Write-Host "  [+] License bound        - Owner $ownerShort confirmed" -ForegroundColor Green
                }
                elseif (Test-DelegationOffer $BurnerAddress $OWNER_ADDRESS) {
                    Write-Host "  [~] Offer received       - Waiting for your node to accept automatically..." -ForegroundColor Yellow
                }
                else {
                    Write-Host "  [ ] Waiting for license  - Bind at " -NoNewline -ForegroundColor DarkGray
                    Write-Host "https://node.hptestingsite.com/licenses" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "  [+] License bound" -ForegroundColor Green
            }

            # Both done?
            if ($gasOk -and $delegationOk) {
                Write-Host ""
                Write-Host "  =========================================" -ForegroundColor Green
                Write-Host "    All done! Your node is fully active!    " -ForegroundColor Green
                Write-Host "  =========================================" -ForegroundColor Green
                Write-Host ""
                Write-Host "  Your node will now automatically process verification"
                Write-Host "  tasks and earn rewards. No further action needed."
                Print-ManageInstructions
                return
            }

            Write-Host ""

            # Countdown
            for ($remaining = $POLL_INTERVAL; $remaining -gt 0; $remaining--) {
                Write-Host "`r  Next check in ${remaining}s...  " -NoNewline -ForegroundColor DarkGray
                Start-Sleep -Seconds 1
            }

            # Move cursor back to overwrite status lines
            $linesToClear = [Console]::CursorTop - $cursorTop
            [Console]::SetCursorPosition(0, $cursorTop)
            for ($k = 0; $k -lt $linesToClear; $k++) {
                Write-Host (" " * [Console]::WindowWidth)
            }
            [Console]::SetCursorPosition(0, $cursorTop)
        }
    }
    catch {
        # Ctrl+C or other interrupt
    }
    finally {
        Write-Host ""
        Write-Host ""
        Print-Info "No worries - your node is still running in the background!"
        Print-Info "Come back and re-run this script anytime to check your setup status."
        Print-ManageInstructions
    }
}

# ─────────────────────────────────────────
# Post-launch flow
# ─────────────────────────────────────────
function Start-PostLaunchFlow {
    Write-Host "  Reading your node's wallet address..." -ForegroundColor Cyan
    Write-Host "  (This may take a few seconds on first start while the wallet is generated)" -ForegroundColor DarkGray
    Write-Host ""

    $burnerAddress = Get-BurnerAddress

    if (-not $burnerAddress) {
        Print-Warn "Could not read wallet address automatically."
        Write-Host ""
        Write-Host "  This sometimes happens on first start. You can find it manually:"
        Write-Host "  Run: " -NoNewline
        Write-Host "docker logs $CONTAINER_NAME 2>&1 | Select -First 20" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  After you find the wallet address, do these two things:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  1. Go to " -NoNewline
        Write-Host "https://node.hptestingsite.com/licenses" -ForegroundColor Cyan
        Write-Host "     and bind your license to that node wallet address"
        Write-Host ""
        Write-Host "  2. Send some gas (tokens) to that node wallet address"
        Write-Host "     (Your node needs gas to submit transactions on-chain)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Then re-run this script - it will detect everything and confirm your setup."
        Print-ManageInstructions
        return
    }

    Display-Wallet $burnerAddress
    Start-Polling $burnerAddress
}

# ─────────────────────────────────────────
# Launch container
# ─────────────────────────────────────────
function Start-LaunchContainer {
    # Check Docker
    $dockerPath = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $dockerPath) {
        Print-Error "Docker is not installed!"
        Write-Host "  Your node runs inside Docker. Please install it first:"
        Write-Host "  https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  After installing Docker, run this script again."
        exit 1
    }
    $null = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Print-Error "Docker is installed but not running!"
        Write-Host "  Please open the Docker Desktop app and wait for it to start,"
        Write-Host "  then run this script again."
        exit 1
    }

    $dataDir = Join-Path $HP_NODE_DIR "data\$CONTAINER_NAME"
    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
    if (-not (Test-Path $CONFIG_DIR)) { New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null }

    # Pull latest image
    Write-Host ""
    Write-Host "  Downloading the latest node software..." -ForegroundColor Cyan
    # Show pull progress to user (don't capture stdout, only merge stderr)
    docker pull $IMAGE_NAME 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Print-Warn "Could not download the latest version. Using previously downloaded version."
    }

    $latestImageId = $null
    $inspectOut = docker inspect --format "{{.Id}}" $IMAGE_NAME 2>&1
    if ($LASTEXITCODE -eq 0) { $latestImageId = ($inspectOut | Out-String).Trim() }
    if (-not $latestImageId) {
        Print-Error "Could not download the node software."
        Write-Host "  Please check your internet connection and try again."
        exit 1
    }

    # Check if container exists and compare image & config
    $currentImageId = ""
    $containerRunning = $false
    $configChanged = $false

    $null = docker inspect $CONTAINER_NAME 2>&1
    if ($LASTEXITCODE -eq 0) {
        $currentImageId = (docker inspect --format "{{.Image}}" $CONTAINER_NAME 2>&1 | Out-String).Trim()
        $stateRunning = (docker inspect --format "{{.State.Running}}" $CONTAINER_NAME 2>&1 | Out-String).Trim()
        if ($stateRunning -eq "true") { $containerRunning = $true }

        # Check config changes
        $envOutput = (docker inspect --format "{{range .Config.Env}}{{println .}}{{end}}" $CONTAINER_NAME 2>&1 | Out-String)
        $envLines = $envOutput -split "\r?\n" | ForEach-Object { $_.Trim() }
        $runningOwner = ($envLines | Where-Object { $_ -match "^OWNERS_ALLOWLIST=" }) -replace "^OWNERS_ALLOWLIST=", ""
        $runningKey = ($envLines | Where-Object { $_ -match "^ETH_PRIVATE_KEY=" }) -replace "^ETH_PRIVATE_KEY=", ""
        $runningLogLevel = ($envLines | Where-Object { $_ -match "^LOG_LEVEL=" }) -replace "^LOG_LEVEL=", ""
        if ($runningOwner -ne $OWNER_ADDRESS -or $runningKey -ne $ETH_PRIVATE_KEY -or $runningLogLevel -ne $LOG_LEVEL) {
            $configChanged = $true
        }
    }

    # Force restart if "Generate new wallet" and cache exists
    if ($FORCE_NEW_WALLET -and -not $configChanged) {
        $cacheFile = Join-Path $dataDir "flohive-cache.json"
        if (Test-Path $cacheFile) { $configChanged = $true }
    }

    # Check if cached wallet key differs from desired key
    if ($ETH_PRIVATE_KEY -and -not $configChanged) {
        $cacheFile = Join-Path $dataDir "flohive-cache.json"
        if (Test-Path $cacheFile) {
            try {
                $cacheJson = Get-Content $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $cachedKey = $cacheJson.burnerWallet.privateKey -replace "^0x", ""
                if ($cachedKey -and $cachedKey -ne $ETH_PRIVATE_KEY) { $configChanged = $true }
            }
            catch { }
        }
    }

    # Already running + up to date
    if ($containerRunning -and -not $configChanged -and $currentImageId -eq $latestImageId) {
        Save-Config
        Write-Host ""
        Write-Host "  =========================================" -ForegroundColor Green
        Write-Host "    Your node is already running!           " -ForegroundColor Green
        Write-Host "  =========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Everything is up to date. Checking your setup status..."
        Write-Host ""
        Start-PostLaunchFlow
        return
    }

    if ($containerRunning -and $configChanged) {
        Write-Host "  Settings changed. Restarting your node with the new settings..." -ForegroundColor Yellow
    }
    elseif ($containerRunning) {
        Write-Host "  A newer version is available. Updating your node..." -ForegroundColor Yellow
    }
    else {
        Write-Host "  Starting your node..." -ForegroundColor Cyan
    }
    Write-Host ""

    # Stop and remove existing container
    $null = docker rm -f $CONTAINER_NAME 2>&1

    # Manage wallet cache
    $cacheFile = Join-Path $dataDir "flohive-cache.json"
    if ($FORCE_NEW_WALLET) {
        Write-Host "  Clearing wallet cache (generating new wallet)..." -ForegroundColor DarkGray
        if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }
    }
    elseif ($ETH_PRIVATE_KEY) {
        $needsWrite = $false
        if (-not (Test-Path $cacheFile)) {
            $needsWrite = $true
        }
        else {
            try {
                $cacheJson = Get-Content $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                $cachedKey = $cacheJson.burnerWallet.privateKey -replace "^0x", ""
                if ($cachedKey -ne $ETH_PRIVATE_KEY) { $needsWrite = $true }
            }
            catch { $needsWrite = $true }
        }
        if ($needsWrite) {
            Write-WalletCache $dataDir $ETH_PRIVATE_KEY
            Write-Host "  Wallet cache updated (address will be derived on startup)" -ForegroundColor DarkGray
        }
    }

    # Run container (capture output to check for errors)
    $dockerRunOutput = docker run -d `
        -e "OWNERS_ALLOWLIST=$OWNER_ADDRESS" `
        -e "ETH_PRIVATE_KEY=$ETH_PRIVATE_KEY" `
        -e "LOG_LEVEL=$LOG_LEVEL" `
        -e "HTTP_PROXY=" `
        -e "HTTPS_PROXY=" `
        -e "http_proxy=" `
        -e "https_proxy=" `
        -v "${dataDir}:/app/cache" `
        --name $CONTAINER_NAME `
        $IMAGE_NAME 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        # Show the docker error so user can diagnose
        $errMsg = ($dockerRunOutput | Out-String).Trim()
        if ($errMsg) { Write-Host "  $errMsg" -ForegroundColor Red }
        Print-Error "Failed to start the node."
        Write-Host "  Common fixes:"
        Write-Host "    - Make sure Docker Desktop is running"
        Write-Host "    - Try restarting Docker and running this script again"
        Write-Host "    - If the problem persists, ask for help in the community"
        exit 1
    }

    Save-Config

    Write-Host ""
    Write-Host "  =========================================" -ForegroundColor Green
    Write-Host "    Node started successfully!              " -ForegroundColor Green
    Write-Host "  =========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Your node is now running. Let's get it fully set up."
    Write-Host ""

    Start-PostLaunchFlow
}

# ─────────────────────────────────────────
# Restart mode
# ─────────────────────────────────────────
if ($RESTART) {
    Print-Banner

    if ($ARG_NAME) {
        if (-not (Load-Config $ARG_NAME)) {
            Print-Error "No saved config found for '$ARG_NAME'."
            Write-Host "  Run start.cmd to set up a new node first."
            exit 1
        }
        Write-Host "  Loaded config for: $CONTAINER_NAME"
    }
    else {
        $configs = Get-ConfigList
        if ($configs.Count -eq 0) {
            Print-Error "No saved configuration found."
            Write-Host "  Run start.cmd to set up a new node first."
            exit 1
        }
        elseif ($configs.Count -eq 1) {
            $name = $configs[0].BaseName
            Load-Config $name | Out-Null
            Write-Host "  Loaded config for: $CONTAINER_NAME"
        }
        else {
            Print-Error "Multiple nodes found. Please specify which one to restart."
            Write-Host ""
            foreach ($f in $configs) { Write-Host "  - $($f.BaseName)" }
            Write-Host ""
            Write-Host "  Usage: start.cmd --restart --container-name <name>"
            exit 1
        }
    }

    # CLI overrides
    if ($ARG_OWNER) {
        if (-not (Test-EthAddress $ARG_OWNER)) {
            Print-Error "Invalid address format. Expected 0x followed by 40 hex characters."
            exit 1
        }
        $OWNER_ADDRESS = $ARG_OWNER
    }
    if ($ARG_KEY) {
        $ETH_PRIVATE_KEY = Strip-0xPrefix $ARG_KEY
        if (-not (Test-PrivateKey $ETH_PRIVATE_KEY)) {
            Print-Error "Invalid private key. Expected 64 hex characters."
            exit 1
        }
        $HAS_CUSTOM_KEY = "true"
    }
    if ($VERBOSE) { $LOG_LEVEL = "debug" }

    Start-LaunchContainer
    exit 0
}

# ─────────────────────────────────────────
# Non-interactive mode: env vars or CLI args
# ─────────────────────────────────────────
$HAS_CLI_ARGS = ($ARG_OWNER -or $ARG_KEY -or $ARG_NAME)

# OWNER_ADDRESS set via env var (no CLI args)
if ($env:OWNER_ADDRESS -and -not $HAS_CLI_ARGS) {
    $OWNER_ADDRESS = $env:OWNER_ADDRESS
    if (-not (Test-EthAddress $OWNER_ADDRESS)) {
        Print-Error "Invalid OWNER_ADDRESS env var. Expected 0x followed by 40 hex characters."
        exit 1
    }
    $CONTAINER_NAME = if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { "hp-verification-node-plugin" }
    $HAS_CUSTOM_KEY = "false"
    $ETH_PRIVATE_KEY = ""
    if ($env:ETH_PRIVATE_KEY) {
        $ETH_PRIVATE_KEY = Strip-0xPrefix $env:ETH_PRIVATE_KEY
        $HAS_CUSTOM_KEY = "true"
    }
    Start-LaunchContainer
    exit 0
}

# CLI args provided -> non-interactive with wizard pre-fill
if ($HAS_CLI_ARGS -and -not $ARG_OWNER -and -not $env:OWNER_ADDRESS) {
    # Special case: only --container-name or --private-key without --owner-address
    # Fall through to wizard
}
elseif ($HAS_CLI_ARGS -and ($ARG_OWNER -or $env:OWNER_ADDRESS)) {
    $OWNER_ADDRESS = if ($ARG_OWNER) { $ARG_OWNER } else { $env:OWNER_ADDRESS }
    if (-not (Test-EthAddress $OWNER_ADDRESS)) {
        Print-Error "Invalid address format. Expected 0x followed by 40 hex characters."
        exit 1
    }
    $CONTAINER_NAME = if ($ARG_NAME) { $ARG_NAME } else { if ($env:CONTAINER_NAME) { $env:CONTAINER_NAME } else { "hp-verification-node-plugin" } }
    $HAS_CUSTOM_KEY = "false"
    $ETH_PRIVATE_KEY = ""
    if ($ARG_KEY) {
        $ETH_PRIVATE_KEY = Strip-0xPrefix $ARG_KEY
        if (-not (Test-PrivateKey $ETH_PRIVATE_KEY)) {
            Print-Error "Invalid private key. Expected 64 hex characters."
            exit 1
        }
        $HAS_CUSTOM_KEY = "true"
    }
    Start-LaunchContainer
    exit 0
}

# ─────────────────────────────────────────
# Interactive Setup Wizard
# ─────────────────────────────────────────
Print-Banner

$IS_EXISTING_NODE = $false
$DEFAULT_OWNER = ""
$DEFAULT_KEY = ""
$DEFAULT_NAME = ""

# Check for saved configurations
$configs = Get-ConfigList
if ($configs.Count -gt 0 -and -not $HAS_CLI_ARGS) {
    Write-Host "  Found previously configured nodes:"
    Write-Host ""

    $configNames = @()
    $idx = 1
    foreach ($f in $configs) {
        $name = $f.BaseName
        $configNames += $name
        $cfgOwner = (Get-Content $f.FullName | Where-Object { $_ -match "^OWNER_ADDRESS=" }) -replace "^OWNER_ADDRESS=", ""
        Write-Host "  $idx) $name  ($cfgOwner)"
        $idx++
    }
    Write-Host "  $idx) Set up a new node"
    Write-Host ""

    while ($true) {
        $selection = Read-Host "  Select an option [1] (press Enter for 1)"
        if (-not $selection) { $selection = "1" }

        if ($selection -eq "$idx") { break }  # New node

        $selNum = 0
        if ([int]::TryParse($selection, [ref]$selNum) -and $selNum -ge 1 -and $selNum -lt $idx) {
            $selectedName = $configNames[$selNum - 1]
            if (Load-Config $selectedName) {
                $DEFAULT_OWNER = $OWNER_ADDRESS
                if ($HAS_CUSTOM_KEY -eq "true") {
                    $DEFAULT_KEY = $ETH_PRIVATE_KEY
                } else {
                    # Try to read cached wallet key from flohive-cache.json
                    $cacheFile = Join-Path $HP_NODE_DIR "data\$CONTAINER_NAME\flohive-cache.json"
                    if (Test-Path $cacheFile) {
                        $cacheContent = Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue
                        if ($cacheContent -match '"privateKey"\s*:\s*"([^"]+)"') {
                            $cachedKey = $Matches[1] -replace '^0x', ''
                            if ($cachedKey -match '^[0-9a-fA-F]{64}$') {
                                $DEFAULT_KEY = $cachedKey
                            }
                        }
                    }
                }
                $DEFAULT_NAME = $CONTAINER_NAME
                if ($VERBOSE) { $LOG_LEVEL = "debug" }
                $IS_EXISTING_NODE = $true
                Print-Success "Loaded config: $selectedName"
                break
            }
        }
        Print-Error "Invalid selection. Please enter a number between 1 and $idx."
    }
}
elseif (-not $HAS_CLI_ARGS) {
    Write-Host "  This wizard will guide you through setting up your"
    Write-Host "  Humanity Protocol verification node step by step."
}

Write-Host ""
Write-Host "  Press Ctrl+C at any time to cancel." -ForegroundColor DarkGray

$TOTAL_STEPS = 5
$CURRENT_STEP = 1

# ── Step 1: Docker ──
Print-Step 1 $TOTAL_STEPS "Checking Prerequisites" -ShowBack $false

$dockerPath = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerPath) {
    Print-Error "Docker is not installed."
    Write-Host ""
    Write-Host "  Your node runs inside Docker - it's a free tool that only takes a minute to install."
    Write-Host "  Download it here: " -NoNewline
    Write-Host "https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  After installing, run this script again."
    exit 1
}
$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Print-Error "Docker is installed but not running."
    Write-Host ""
    Write-Host "  Please open the Docker Desktop app and wait until it says `"running`","
    Write-Host "  then run this script again."
    exit 1
}
Print-Success "Docker is ready."

# ── Steps 2-5 with back navigation ──
$CURRENT_STEP = 2

while ($CURRENT_STEP -le 5) {

    # ── Step 2: Node Name ──
    if ($CURRENT_STEP -eq 2) {
        Print-Step 2 $TOTAL_STEPS "Name Your Node" -ShowBack $false

        if ($IS_EXISTING_NODE) {
            $CONTAINER_NAME = $DEFAULT_NAME
            Print-Success "Node name: $CONTAINER_NAME (existing node)"
            $CURRENT_STEP = 3
            continue
        }
        if ($ARG_NAME) {
            $CONTAINER_NAME = $ARG_NAME
            Print-Success "Node name: $CONTAINER_NAME"
            $CURRENT_STEP = 3
            continue
        }

        $defaultContainer = if ($CONTAINER_NAME) { $CONTAINER_NAME } else { "hp-verification-node-plugin" }
        Write-Host "  Give your node a name to identify it."
        Write-Host "  (Only letters, numbers, hyphens, underscores, and dots are allowed)" -ForegroundColor DarkGray
        Write-Host ""

        $step2Back = $false
        while ($true) {
            $customName = Read-Host "  Node name (press Enter for $defaultContainer)"
            $customName = $customName.Trim()

            if ($customName -in "b", "B", "back", "Back") {
                Write-Host "  This is the first step." -ForegroundColor DarkGray
                $step2Back = $true
                break
            }
            if (-not $customName) { $CONTAINER_NAME = $defaultContainer; break }
            if ($customName -match "^[a-zA-Z0-9][a-zA-Z0-9_.\-]*$") {
                $CONTAINER_NAME = $customName; break
            }
            Print-Error "Invalid name. Use only letters, numbers, hyphens, underscores, and dots."
        }
        if ($step2Back) { continue }
        Print-Success "Node name: $CONTAINER_NAME"
        $CURRENT_STEP = 3
        continue
    }

    # ── Step 3: License Owner ──
    if ($CURRENT_STEP -eq 3) {
        $canGoBack = -not $IS_EXISTING_NODE -and -not $ARG_NAME
        Print-Step 3 $TOTAL_STEPS "License Owner Address" -ShowBack $canGoBack

        if ($ARG_OWNER) {
            $OWNER_ADDRESS = $ARG_OWNER
            if (-not (Test-EthAddress $OWNER_ADDRESS)) {
                Print-Error "Invalid address format. Expected 0x followed by 40 hex characters."
                Print-Info "Example: 0x1234567890abcdef1234567890abcdef12345678"
                exit 1
            }
            Print-Success "Owner Address: $OWNER_ADDRESS"
            $CURRENT_STEP = 4
            continue
        }

        Write-Host "  This is the wallet address where you own (or will own) the License NFT."
        Write-Host "  It starts with 0x and is 42 characters long." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Don't have a License NFT yet? Purchase one at:"
        Write-Host "  https://sale.staging.humanity.org/" -ForegroundColor Cyan
        Write-Host ""

        $step3Default = if ($OWNER_ADDRESS) { $OWNER_ADDRESS } elseif ($DEFAULT_OWNER) { $DEFAULT_OWNER } else { "" }

        while ($true) {
            if ($step3Default) {
                $inputOwner = Read-Host "  Owner Address (press Enter for $step3Default)"
            }
            else {
                $inputOwner = Read-Host "  Owner Address"
            }
            $inputOwner = $inputOwner.Trim()

            if ($inputOwner -in "b", "B", "back", "Back") {
                if (-not $canGoBack) {
                    Write-Host "  This is the first editable step." -ForegroundColor DarkGray
                    continue
                }
                $CURRENT_STEP = 2; break
            }
            if (-not $inputOwner -and $step3Default) {
                $OWNER_ADDRESS = $step3Default; break
            }
            if (-not $inputOwner) {
                Print-Error "Owner Address cannot be empty."; continue
            }
            if (-not (Test-EthAddress $inputOwner)) {
                Print-Error "Invalid format. It should start with 0x followed by 40 hex characters."
                Print-Info "Example: 0x1234567890abcdef1234567890abcdef12345678"
                continue
            }
            $OWNER_ADDRESS = $inputOwner; break
        }
        if ($CURRENT_STEP -eq 2) { continue }
        Print-Success "Owner Address: $OWNER_ADDRESS"
        $CURRENT_STEP = 4
        continue
    }

    # ── Step 4: Node's Burner Wallet ──
    if ($CURRENT_STEP -eq 4) {
        Print-Step 4 $TOTAL_STEPS "Node's Burner Wallet"

        if ($ARG_KEY) {
            $ETH_PRIVATE_KEY = Strip-0xPrefix $ARG_KEY
            if (-not (Test-PrivateKey $ETH_PRIVATE_KEY)) {
                Print-Error "Invalid private key. Expected 64 hex characters (without 0x prefix)."
                exit 1
            }
            $HAS_CUSTOM_KEY = "true"
            $derivedAddr = Derive-EthAddress -PrivKeyHex $ETH_PRIVATE_KEY
            if ($derivedAddr) {
                Print-Success "Private key accepted.  Address: $derivedAddr"
            } else {
                Print-Success "Private key accepted.  (address will be derived on startup)"
            }
            $CURRENT_STEP = 5
            continue
        }

        $existingKey = if ($ETH_PRIVATE_KEY) { $ETH_PRIVATE_KEY } elseif ($DEFAULT_KEY) { $DEFAULT_KEY } else { "" }

        if ($existingKey) {
            $maskedKey = $existingKey.Substring(0, 6) + "..." + $existingKey.Substring($existingKey.Length - 4)
            Write-Host "  Your node's wallet key: $maskedKey"
            Write-Host ""
            Write-Host "  1) Keep current wallet (default)"
            Write-Host "  2) Use a different wallet"
            Write-Host "  3) Generate a new wallet"
            Write-Host ""

            while ($true) {
                $keyChoice = Read-Host "  Select (press Enter for 1 = Keep current)"
                $keyChoice = $keyChoice.Trim()

                if ($keyChoice -in "b", "B", "back", "Back") {
                    $CURRENT_STEP = 3; break
                }
                if (-not $keyChoice -or $keyChoice -eq "1") {
                    $ETH_PRIVATE_KEY = $existingKey; $HAS_CUSTOM_KEY = "true"
                    Print-Success "Keeping current wallet."
                    break
                }
                if ($keyChoice -eq "2") {
                    Write-Host ""
                    Write-Host "  Enter your wallet's private key (64 hex characters, without 0x)."
                    Write-Host "  (Press Enter to go back)" -ForegroundColor DarkGray
                    Write-Host ""

                    $enteredKey = Read-Host "  Private Key" -AsSecureString
                    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($enteredKey)
                    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    $plainKey = $plainKey.Trim()

                    if (-not $plainKey) { continue }
                    $plainKey = Strip-0xPrefix $plainKey
                    if (-not (Test-PrivateKey $plainKey)) {
                        Print-Error "Invalid format. Expected 64 hex characters."
                        continue
                    }
                    $ETH_PRIVATE_KEY = $plainKey; $HAS_CUSTOM_KEY = "true"
                    $derivedAddr = Derive-EthAddress -PrivKeyHex $ETH_PRIVATE_KEY
                    if ($derivedAddr) {
                        Print-Success "Private key accepted.  Address: $derivedAddr"
                    } else {
                        Print-Success "Private key accepted.  (address will be derived on startup)"
                    }
                    break
                }
                if ($keyChoice -eq "3") {
                    $ETH_PRIVATE_KEY = ""; $HAS_CUSTOM_KEY = "false"; $FORCE_NEW_WALLET = $true
                    Print-Info "A new wallet will be created when the node starts."
                    Print-Warn "You will need to fund it with HP tokens for gas fees."
                    break
                }
                Print-Error "Please enter 1, 2, or 3."
            }
            if ($CURRENT_STEP -eq 3) { continue }
        }
        else {
            Write-Host "  Your node needs its own wallet to operate on the network."
            Write-Host "  Most users let the node create a new one automatically."
            Write-Host ""
            Write-Host "  1) Generate a new wallet automatically (recommended)"
            Write-Host "  2) Use my own wallet (I already have a funded wallet)"
            Write-Host ""

            while ($true) {
                $walletChoice = Read-Host "  Select (press Enter for 1 = Generate new)"
                $walletChoice = $walletChoice.Trim()

                if ($walletChoice -in "b", "B", "back", "Back") {
                    $CURRENT_STEP = 3; break
                }
                if (-not $walletChoice -or $walletChoice -eq "1") {
                    $ETH_PRIVATE_KEY = ""; $HAS_CUSTOM_KEY = "false"
                    Print-Info "A new wallet will be created when the node starts."
                    Print-Warn "You will need to fund it with HP tokens for gas fees."
                    break
                }
                if ($walletChoice -eq "2") {
                    Write-Host ""
                    Write-Host "  Enter your wallet's private key (64 hex characters, without 0x)."
                    Write-Host "  (Press Enter to go back)" -ForegroundColor DarkGray
                    Write-Host ""

                    $enteredKey = Read-Host "  Private Key" -AsSecureString
                    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($enteredKey)
                    $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                    $plainKey = $plainKey.Trim()

                    if (-not $plainKey) { continue }
                    $plainKey = Strip-0xPrefix $plainKey
                    if (-not (Test-PrivateKey $plainKey)) {
                        Print-Error "Invalid format. Expected 64 hex characters."
                        continue
                    }
                    $ETH_PRIVATE_KEY = $plainKey; $HAS_CUSTOM_KEY = "true"
                    $derivedAddr = Derive-EthAddress -PrivKeyHex $ETH_PRIVATE_KEY
                    if ($derivedAddr) {
                        Print-Success "Private key accepted.  Address: $derivedAddr"
                    } else {
                        Print-Success "Private key accepted.  (address will be derived on startup)"
                    }
                    break
                }
                Print-Error "Please enter 1 or 2."
            }
            if ($CURRENT_STEP -eq 3) { continue }
        }

        $CURRENT_STEP = 5
        continue
    }

    # ── Step 5: Review & Launch ──
    if ($CURRENT_STEP -eq 5) {
        Print-Step 5 $TOTAL_STEPS "Review & Launch"

        Write-Host "  Please review your settings before starting:"
        Write-Host ""
        Write-Host "  Node Name      : $CONTAINER_NAME"
        Write-Host "  License Owner  : $OWNER_ADDRESS"
        if ($HAS_CUSTOM_KEY -eq "true") {
            $reviewAddr = Derive-EthAddress $ETH_PRIVATE_KEY
            if ($reviewAddr) {
                Write-Host "  Node's Burner Wallet    : $reviewAddr"
            } else {
                $maskedReview = $ETH_PRIVATE_KEY.Substring(0, 6) + "..." + $ETH_PRIVATE_KEY.Substring($ETH_PRIVATE_KEY.Length - 4)
                Write-Host "  Node's Burner Wallet    : $maskedReview (key; address derived on startup)"
            }
        }
        else {
            Write-Host "  Node's Burner Wallet    : (will be generated on first start)"
        }
        Write-Host "  Log Level      : $LOG_LEVEL"
        Write-Host ""
        Write-Host "  Data stored at : $HP_NODE_DIR\data\$CONTAINER_NAME"
        Write-Host "  Config saved to: $CONFIG_DIR\$CONTAINER_NAME.conf"
        Write-Host ""

        while ($true) {
            $confirm = Read-Host "  Start your node? (press Enter for Yes / n to cancel)"
            $confirm = $confirm.Trim().ToLower()

            if ($confirm -in "b", "back") {
                $CURRENT_STEP = 4; break
            }
            if (-not $confirm -or $confirm -in "y", "yes") {
                $CURRENT_STEP = 6; break  # Exit loop
            }
            if ($confirm -in "n", "no") {
                Write-Host ""
                Print-Info "Setup cancelled. Run start.cmd again when you're ready."
                exit 0
            }
            Print-Error "Please enter 'y', 'n', or 'b'."
        }
        continue
    }
}

# Launch
Start-LaunchContainer
