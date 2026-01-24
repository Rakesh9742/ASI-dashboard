const bcrypt = require('bcryptjs');

// Generate password hash for default users
// Default password for all users: "password123"
const password = 'password123';

bcrypt.hash(password, 10, (err, hash) => {
  if (err) {
    console.error('Error generating hash:', err);
    return;
  }
  console.log('Password hash for "password123":');
  console.log(hash);
  console.log('\nCopy this hash to the migration file.');
});































