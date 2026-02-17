#!/bin/bash
# Test script for ghcp network isolation
# Run this from within a ghcp session to verify firewall is working

echo "=== Testing ghcp Network Isolation ==="
echo ""

echo "Test 1: Public internet (should work)"
node -e "fetch('https://api.github.com').then(r => console.log('  ✓ Public internet accessible - Status:', r.status)).catch(e => console.log('  ✗ Failed:', e.message))"
echo ""

echo "Test 2: Local network (should be blocked)"
node -e "const controller = new AbortController(); setTimeout(() => controller.abort(), 5000); fetch('http://192.168.5.121:2283', {signal: controller.signal}).then(r => console.log('  ✗ Local network accessible (BAD) - Status:', r.status)).catch(e => console.log('  ✓ Local network blocked (GOOD):', e.message))"
echo ""

echo "Test 3: Container localhost (should work)"
# Start a simple Node HTTP server in background
node -e "const http = require('http'); const server = http.createServer((req, res) => { res.writeHead(200); res.end('OK'); }); server.listen(9999, '127.0.0.1');" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 2
node -e "fetch('http://127.0.0.1:9999').then(r => console.log('  ✓ Container localhost accessible - Status:', r.status)).catch(e => console.log('  ✗ Failed:', e.message))"
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

echo ""
echo "=== Summary ==="
echo "✓ = Expected behavior"
echo "✗ = Unexpected behavior"
