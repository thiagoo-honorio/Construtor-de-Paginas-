param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Arquivo,
    [int]$Porta = 8765,
    [switch]$NaoAbrir
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Arquivo -PathType Leaf)) {
    throw "Arquivo não encontrado: $Arquivo"
}
$caminho = (Resolve-Path -LiteralPath $Arquivo).Path
$pasta = Split-Path -Parent $caminho
$nome = Split-Path -Leaf $caminho

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'node não encontrado no PATH. Este script usa o node para servir o arquivo.'
}

# Variáveis de ambiente evitam problemas de aspas/acentos nos argumentos nativos.
$env:APB_SER_DIR = $pasta
$env:APB_SER_ARQUIVO = $nome
$env:APB_SER_PORTA = [string]$Porta
$env:APB_SER_ABRIR = if ($NaoAbrir) { '0' } else { '1' }

$servidor = @'
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const raiz = path.resolve(process.env.APB_SER_DIR || '.');
const nomeArquivo = process.env.APB_SER_ARQUIVO || 'index.html';
let porta = Math.max(1, Math.min(65535, parseInt(process.env.APB_SER_PORTA, 10) || 8765));
const abrir = process.env.APB_SER_ABRIR === '1';
let tentativas = 20;
let iniciado = false;

const tipos = {
  '.html': 'text/html; charset=utf-8',
  '.htm': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.pdf': 'application/pdf'
};

const server = http.createServer(function (req, res) {
  let caminhoUrl;
  try {
    caminhoUrl = decodeURIComponent((req.url || '/').split('?')[0].split('#')[0]);
  } catch (e) {
    res.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' }).end('URL inválida');
    return;
  }
  if (caminhoUrl === '/' || caminhoUrl === '') caminhoUrl = '/' + nomeArquivo;
  const alvo = path.resolve(raiz, '.' + caminhoUrl);
  if (alvo !== raiz && !alvo.startsWith(raiz + path.sep)) {
    res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Acesso negado');
    return;
  }
  fs.stat(alvo, function (erro, st) {
    if (erro || !st.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Arquivo não encontrado: ' + caminhoUrl);
      return;
    }
    res.writeHead(200, {
      'Content-Type': tipos[path.extname(alvo).toLowerCase()] || 'application/octet-stream',
      'Content-Length': st.size,
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    if (req.method === 'HEAD') { res.end(); return; }
    fs.createReadStream(alvo).pipe(res);
  });
});

server.on('error', function (erro) {
  if (!iniciado && erro.code === 'EADDRINUSE' && tentativas > 0) {
    tentativas -= 1;
    porta += 1;
    server.listen(porta, '127.0.0.1');
    return;
  }
  console.error('Não foi possível iniciar o servidor:', erro.message);
  process.exit(1);
});

server.listen(porta, '127.0.0.1', function () {
  iniciado = true;
  const url = 'http://localhost:' + porta + '/' + encodeURIComponent(nomeArquivo);
  console.log('Servindo: ' + path.join(raiz, nomeArquivo));
  console.log('Acesse: ' + url);
  console.log('Pressione Ctrl+C para encerrar.');
  if (abrir) {
    // Aspas montadas por código: o Windows PowerShell quebra aspas duplas em `node -e`.
    const q = String.fromCharCode(34);
    exec('start ' + q + q + ' ' + q + url + q, function (erro) {
      if (erro) console.error('Não foi possível abrir o navegador automaticamente. Abra o endereço acima.');
    });
  }
});
'@

& node -e $servidor
