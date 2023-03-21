param (
	[parameter(Mandatory=$false)]
	[String]$conf_name
)

$config_name = ""

if ($conf_name.Length -gt 0) 
{
	$config_name = $conf_name
} 
else 
{
	$config_name = Read-Host "Enter configuration file name"
}

# Создание директорий для конфигов
New-Item -ItemType Directory -Path "/config/client_configs" -ErrorAction SilentlyContinue
$config_current_peer_dir = New-Item -ItemType Directory -Path "/config/client_configs/$config_name" -ErrorAction SilentlyContinue

# Определение октета для нового пользователя
$wg0_conf_path = "/config/wg0.conf"
$octet_pattern = "(AllowedIPs = 192\.168\.89\.)(\d+)(\/.*)"

$next_octet = 2
$contents = Get-Content -Path $wg0_conf_path

foreach ($line in $contents) {
	$matches = $line | Select-String -Pattern $octet_pattern
	if ($matches) {
		$next_octet = [int]$matches.Matches.Groups[2].Value + 1
	}
}

# Генерация ключей для нового пользователя

$client_private_key_path = "$config_current_peer_dir\client_$next_octet.pri"
$client_public_key_path = "$config_current_peer_dir\client_$next_octet.pub"
$client_preshared_key_path = "$config_current_peer_dir\client_$next_octet.psk"

$cmd = "umask 077; wg genkey > $client_private_key_path; Get-Content $client_private_key_path | wg pubkey > $client_public_key_path; wg genpsk > $client_preshared_key_path"

Invoke-Expression -Command $cmd

# Создание конфигурационного файла для нового пользователя
$server_config = @"
# BEGIN_PEER $config_name
[Peer]
PublicKey = $(Get-Content -Path $client_public_key_path)
PresharedKey = $(Get-Content -Path $client_preshared_key_path)
AllowedIPs = 192.168.89.$next_octet/32
# END_PEER $config_name
"@
Add-Content -Path $wg0_conf_path -Value $server_config

$client_config = @"
[Interface]
PrivateKey = $(Get-Content -Path $client_private_key_path)
Address = 192.168.89.$next_octet/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $(Get-Content -Path $wg0_conf_path | Where-Object { $_ -like "*PrivateKey*" } | Select-String -Pattern '(?<=PrivateKey = )(\S+)' | Select-Object -ExpandProperty Matches | Select-Object -First 1 -ExpandProperty Value | wg pubkey)
PresharedKey = $(Get-Content -Path $client_preshared_key_path)
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = vpn.continuedev.ru:44121
PersistentKeepalive = 25
"@
$client_config_path = "$config_current_peer_dir\$config_name.conf"

Set-Content -Path $client_config_path -Value $client_config

# Удаление сгенерированных файлов с ключами
Remove-Item -Path "$client_private_key_path", "$client_public_key_path", "$client_preshared_key_path" -Force

Write-Host "Пользователь $config_name создан. IP-адрес: 192.168.89.$next_octet"

# Генерация QR Code
Invoke-Expression -Command "Get-Content $client_config_path | qrencode -o $config_current_peer_dir/qr.png"
Invoke-Expression -Command "Get-Content $client_config_path | qrencode -t ansiutf8"

# Перезапуск интерфейса
Invoke-Expression -Command "wg-quick down wg0 && wg-quick up wg0"