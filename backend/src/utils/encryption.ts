import crypto from 'crypto';

// Encryption key - should be stored in environment variable
// For production, use a strong random key (32 bytes for AES-256)
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY || crypto.randomBytes(32).toString('hex');
const ALGORITHM = 'aes-256-cbc';
const IV_LENGTH = 16; // For AES, this is always 16

/**
 * Encrypts a string value
 * @param text - The text to encrypt
 * @returns Encrypted string in format: iv:encryptedData (both base64 encoded)
 */
export function encrypt(text: string): string {
  try {
    // Ensure we have a 32-byte key (64 hex characters)
    const key = Buffer.from(ENCRYPTION_KEY.slice(0, 64).padEnd(64, '0'), 'hex');
    
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(ALGORITHM, key, iv);
    
    let encrypted = cipher.update(text, 'utf8', 'base64');
    encrypted += cipher.final('base64');
    
    // Return iv:encryptedData format
    return `${iv.toString('base64')}:${encrypted}`;
  } catch (error) {
    console.error('Encryption error:', error);
    throw new Error('Failed to encrypt data');
  }
}

/**
 * Decrypts an encrypted string
 * @param encryptedText - The encrypted text in format: iv:encryptedData
 * @returns Decrypted string
 */
export function decrypt(encryptedText: string): string {
  try {
    // Ensure we have a 32-byte key (64 hex characters)
    const key = Buffer.from(ENCRYPTION_KEY.slice(0, 64).padEnd(64, '0'), 'hex');
    
    const parts = encryptedText.split(':');
    if (parts.length !== 2) {
      throw new Error('Invalid encrypted format');
    }
    
    const iv = Buffer.from(parts[0], 'base64');
    const encrypted = parts[1];
    
    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
    
    let decrypted = decipher.update(encrypted, 'base64', 'utf8');
    decrypted += decipher.final('utf8');
    
    return decrypted;
  } catch (error) {
    console.error('Decryption error:', error);
    throw new Error('Failed to decrypt data');
  }
}

/**
 * Encrypts a number (converts to string first)
 * @param value - The number to encrypt
 * @returns Encrypted string
 */
export function encryptNumber(value: number): string {
  return encrypt(value.toString());
}

/**
 * Decrypts an encrypted number
 * @param encryptedValue - The encrypted value
 * @returns Decrypted number
 */
export function decryptNumber(encryptedValue: string): number {
  return parseInt(decrypt(encryptedValue), 10);
}

