<#
  Executa o pipeline completo: ingestão (Python) -> job do Pentaho (Kitchen).
  Uso, da raiz do repositório:
      powershell -ExecutionPolicy Bypass -File etl\executar_pipeline.ps1
  Opcional: -PentahoDir "C:\Pentaho\data-integration"  (padrão; ou variável PENTAHO_HOME)
  As credenciais vêm do arquivo .env (copiado de .env.example) e são passadas
  ao Kitchen como parâmetros; nada fica gravado nos .ktr/.kjb.
#>
param(
    [string]$PentahoDir = $(if ($env:PENTAHO_HOME) { $env:PENTAHO_HOME } else { "C:\Pentaho\data-integration" })
)
$ErrorActionPreference = "Stop"
$Raiz = Split-Path -Parent $PSScriptRoot

# 1) Lê o .env
$envFile = Join-Path $Raiz ".env"
if (-not (Test-Path $envFile)) { throw "Arquivo .env não encontrado. Rode: Copy-Item .env.example .env" }
$cfg = @{}
Get-Content $envFile -Encoding UTF8 | Where-Object { $_ -match '^\s*[^#].*=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    $cfg[$k.Trim()] = $v.Trim()
}

# 2) Ingestão: repara o JSON bruto e gera data/processed/imoveis.csv
Write-Host "==> 1/2 Ingestão (reparar_json.py)" -ForegroundColor Cyan
$py = if (Get-Command py -ErrorAction SilentlyContinue) { "py" } else { "python" }
& $py (Join-Path $Raiz "ingestion\reparar_json.py")
if ($LASTEXITCODE -ne 0) { throw "Falha na ingestão" }

# 3) Job do Pentaho: staging -> dimensões -> fato
Write-Host "==> 2/2 Pentaho (job_carga_dw.kjb)" -ForegroundColor Cyan
$kitchen = Join-Path $PentahoDir "Kitchen.bat"
if (-not (Test-Path $kitchen)) { throw "Kitchen.bat não encontrado em $PentahoDir" }
$job = Join-Path $Raiz "etl\job_carga_dw.kjb"
$logDir = Join-Path $Raiz "logs"; New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "job_carga_dw.log"
# Kitchen.bat chama Spoon.bat pelo nome: a pasta do Pentaho precisa estar no PATH.
$env:Path = "$PentahoDir;$env:Path"
# Memória moderada para máquinas com pouca RAM
if (-not $env:PENTAHO_DI_JAVA_OPTIONS) { $env:PENTAHO_DI_JAVA_OPTIONS = "-Xms256m -Xmx1536m" }
# Cada /param vai entre aspas: no cmd, o "=" sem aspas separa argumentos.
$params = @(
    "/param:`"PG_HOST=$($cfg['POSTGRES_HOST'])`"", "/param:`"PG_PORT=$($cfg['POSTGRES_PORT'])`"",
    "/param:`"PG_DB=$($cfg['POSTGRES_DB'])`"", "/param:`"PG_USER=$($cfg['POSTGRES_USER'])`"",
    "/param:`"PG_PASSWORD=$($cfg['POSTGRES_PASSWORD'])`""
) -join " "
$cmdLine = "cd /d `"$PentahoDir`" && Kitchen.bat /file:`"$job`" /level:Basic $params"
# Só as linhas de log do Kettle ("data - passo - mensagem"); a linha de comando (com a senha) é descartada.
cmd /c $cmdLine 2>&1 | ForEach-Object { "$_" } |
    Where-Object { $_ -match '^\d{4}/\d{2}/\d{2} .* - ' -and $_ -notmatch 'PG_PASSWORD' } |
    Tee-Object -FilePath $log
if (Select-String -Path $log -Pattern 'Finished with errors|ERROR' -Quiet) {
    throw "Job do Pentaho terminou com erro. Veja $log"
}
Write-Host "Pipeline concluído." -ForegroundColor Green
