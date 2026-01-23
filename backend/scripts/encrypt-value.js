const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// Load .env file to get ENCRYPTION_KEY
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

const envVars = loadEnv();
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY || envVars.ENCRYPTION_KEY;

if (!ENCRYPTION_KEY) {
  console.error('ERROR: ENCRYPTION_KEY not found in .env file or environment variables!');
  console.error('Please make sure ENCRYPTION_KEY is set in backend/.env file');
  process.exit(1);
}

const ALGORITHM = 'aes-256-cbc';
const IV_LENGTH = 16;

function encrypt(text) {
  const key = Buffer.from(ENCRYPTION_KEY.slice(0, 64).padEnd(64, '0'), 'hex');
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
  
  let encrypted = cipher.update(text, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  
  return `${iv.toString('base64')}:${encrypted}`;
}

// Get value from command line argument
const value = process.argv[2];

if (!value) {
  console.error('Usage: node encrypt-value.js <value>');
  console.error('Example: node encrypt-value.js 22');
  process.exit(1);
}

const encrypted = encrypt(value);
console.log(`\n✅ Encrypted value: ${encrypted}`);
console.log(`\n📝 Add this to your .env file:`);
console.log(`SSH_PORT=${encrypted}`);
console.log(`\n💡 Make sure you're using the same ENCRYPTION_KEY that's in your .env file!`);

