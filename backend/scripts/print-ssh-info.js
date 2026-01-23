const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Load .env file
function loadEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (fs.existsSync(envPath)) {
    const envContent = fs.readFileSync(envPath, 'utf8');
    const envVars = {};
    envContent.split('\n').forEach(line => {
      const trimmed = line.trim();
      if (trimmed && !trimmed.startsWith('#')) {
        const [key, ...valueParts] = trimmed.split('=');
        if (key && valueParts.length > 0) {
          envVars[key.trim()] = valueParts.join('=').trim();
        }
      }
    });
    return envVars;
  }
  return {};
}

const env = loadEnv();
const ENCRYPTION_KEY = env.ENCRYPTION_KEY;
const SSH_IP = env.SSH_IP;
const SSH_PORT = env.SSH_PORT;

function decrypt(encryptedText) {
  if (!ENCRYPTION_KEY) {
    return 'ENCRYPTION_KEY not found';
  }
  
  try {
    const key = Buffer.from(ENCRYPTION_KEY.slice(0, 64).padEnd(64, '0'), 'hex');
    const parts = encryptedText.split(':');
    if (parts.length !== 2) {
      return 'Invalid format';
    }
    const iv = Buffer.from(parts[0], 'base64');
    const encrypted = parts[1];
    const decipher = crypto.createDecipheriv('aes-256-cbc', key, iv);
    let decrypted = decipher.update(encrypted, 'base64', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
  } catch (error) {
    return `ERROR: ${error.message}`;
  }
}

console.log('\n═══════════════════════════════════════════════════════════');
console.log('🔐 Current SSH Configuration:');
console.log('═══════════════════════════════════════════════════════════');
console.log(`IP Address: ${SSH_IP || 'Not set'}`);

if (SSH_PORT) {
  try {
    const decryptedPort = decrypt(SSH_PORT);
    console.log(`Port (encrypted): ${SSH_PORT}`);
    console.log(`Port (decrypted): ${decryptedPort}`);
  } catch (e) {
    console.log(`Port (encrypted): ${SSH_PORT}`);
    console.log(`Port (decrypted): ERROR - ${e.message}`);
  }
} else {
  console.log('Port: Not set (default: 22)');
}

console.log(`\nConnection String: ssh -p ${SSH_PORT ? decrypt(SSH_PORT) : '22'} <username>@${SSH_IP || 'NOT_SET'}`);
console.log('═══════════════════════════════════════════════════════════\n');

