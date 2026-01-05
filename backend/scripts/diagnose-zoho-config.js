/**
 * Zoho OAuth Configuration Diagnostic Tool
 * 
 * This script helps diagnose Zoho OAuth configuration issues
 */

require('dotenv').config();

console.log('🔍 Zoho OAuth Configuration Diagnostic\n');
console.log('='.repeat(60));

// Check environment variables
const clientId = process.env.ZOHO_CLIENT_ID;
const clientSecret = process.env.ZOHO_CLIENT_SECRET;
const redirectUri = process.env.ZOHO_REDIRECT_URI;
const authUrl = process.env.ZOHO_AUTH_URL || 'https://accounts.zoho.com';
const apiUrl = process.env.ZOHO_API_URL || 'https://projectsapi.zoho.com';

console.log('\n📋 Current Configuration:');
console.log('-'.repeat(60));
console.log('ZOHO_CLIENT_ID:', clientId ? `${clientId.substring(0, 20)}...` : '❌ NOT SET');
console.log('ZOHO_CLIENT_SECRET:', clientSecret ? `${clientSecret.substring(0, 10)}...` : '❌ NOT SET');
console.log('ZOHO_REDIRECT_URI:', redirectUri || '❌ NOT SET');
console.log('ZOHO_AUTH_URL:', authUrl);
console.log('ZOHO_API_URL:', apiUrl);

// Validation checks
console.log('\n✅ Validation Checks:');
console.log('-'.repeat(60));

let hasErrors = false;

if (!clientId) {
  console.log('❌ ZOHO_CLIENT_ID is missing');
  hasErrors = true;
} else {
  if (clientId.includes(' ') || clientId.includes('\n')) {
    console.log('⚠️  ZOHO_CLIENT_ID may have extra spaces or newlines');
    hasErrors = true;
  } else {
    console.log('✅ ZOHO_CLIENT_ID is set');
  }
}

if (!clientSecret) {
  console.log('❌ ZOHO_CLIENT_SECRET is missing');
  hasErrors = true;
} else {
  if (clientSecret.includes(' ') || clientSecret.includes('\n')) {
    console.log('⚠️  ZOHO_CLIENT_SECRET may have extra spaces or newlines');
    hasErrors = true;
  } else {
    console.log('✅ ZOHO_CLIENT_SECRET is set');
  }
}

if (!redirectUri) {
  console.log('❌ ZOHO_REDIRECT_URI is missing');
  hasErrors = true;
} else {
  console.log('✅ ZOHO_REDIRECT_URI is set');
  
  // Check for common redirect URI issues
  if (redirectUri.endsWith('/')) {
    console.log('⚠️  WARNING: Redirect URI ends with "/" - ensure this matches Zoho Console exactly');
  }
  if (redirectUri.includes(' ')) {
    console.log('❌ ERROR: Redirect URI contains spaces');
    hasErrors = true;
  }
}

// Data center check
console.log('\n🌍 Data Center Configuration:');
console.log('-'.repeat(60));
console.log('Current AUTH_URL:', authUrl);
console.log('Current API_URL:', apiUrl);

const dataCenters = {
  'US': { auth: 'https://accounts.zoho.com', api: 'https://projectsapi.zoho.com' },
  'EU': { auth: 'https://accounts.zoho.eu', api: 'https://projectsapi.zoho.eu' },
  'IN': { auth: 'https://accounts.zoho.in', api: 'https://projectsapi.zoho.in' },
  'AU': { auth: 'https://accounts.zoho.com.au', api: 'https://projectsapi.zoho.com.au' }
};

console.log('\nAvailable data centers:');
Object.entries(dataCenters).forEach(([name, urls]) => {
  const isCurrent = urls.auth === authUrl;
  console.log(`${isCurrent ? '👉' : '  '} ${name}: ${urls.auth}`);
});

console.log('\n📝 Next Steps:');
console.log('-'.repeat(60));
console.log('1. Determine your Zoho account data center:');
console.log('   - Login to your Zoho account');
console.log('   - Check the URL after login (look for .com, .eu, .in, or .com.au)');
console.log('   - Or check: https://accounts.zoho.com/apiauthtoken/create');
console.log('\n2. Verify redirect URI in Zoho Developer Console:');
console.log('   - Go to: https://api-console.zoho.com/ (or .eu/.in/.com.au based on your DC)');
console.log('   - Select your OAuth app');
console.log('   - Check "Authorized Redirect URIs"');
console.log('   - Must match EXACTLY: ' + redirectUri);
console.log('\n3. Verify client credentials:');
console.log('   - Client ID should start with: 1000.');
console.log('   - Client Secret should be a long string');
console.log('   - No extra spaces or newlines');
console.log('\n4. Test the configuration:');
console.log('   - Restart your server after making changes');
console.log('   - Try the OAuth flow again');

if (hasErrors) {
  console.log('\n❌ Configuration has errors. Please fix them before proceeding.');
  process.exit(1);
} else {
  console.log('\n✅ Basic configuration looks good!');
  console.log('If you still get "invalid_client" error, check data center and redirect URI.');
}








