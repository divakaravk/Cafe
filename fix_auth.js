const https = require('https');

const PROJECT_REF = 'vsbjkytdqhzbtideebwy';
const SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzYmpreXRkcWh6YnRpZGVlYnd5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NTA0NDU2NiwiZXhwIjoyMDkwNjIwNTY2fQ.YerUmMU-DPP-LqlXvVydtTCGzxfFLrDwZVsoWzHplvI';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;

const NEW_EMAIL = 'divakaravk437@gmail.com';
const NEW_PASSWORD = 'Admin@123';

async function request(path, method, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, SUPABASE_URL);
    const options = {
      method: method,
      headers: {
        'apikey': SERVICE_ROLE_KEY,
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json'
      }
    };

    const req = https.request(url, options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(data ? JSON.parse(data) : null);
        } else {
          try {
            const err = JSON.parse(data);
            resolve({ error: err });
          } catch (e) {
            resolve({ error: data || res.statusMessage });
          }
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function fix() {
  console.log('--- Step 1: Checking auth.users ---');
  const usersRes = await request('/auth/v1/admin/users', 'GET');
  if (usersRes.error) {
    console.error('Error fetching users:', usersRes.error);
    return;
  }

  const usersList = usersRes.users || [];
  const targetUser = usersList.find(u => u.email === NEW_EMAIL);
  let userId;

  if (targetUser) {
    console.log(`User ${NEW_EMAIL} exists with ID:`, targetUser.id);
    userId = targetUser.id;
    
    console.log(`--- Step 2: resetting password to ${NEW_PASSWORD} ---`);
    const updateRes = await request(`/auth/v1/admin/users/${userId}`, 'PUT', {
      password: NEW_PASSWORD,
      email_confirm: true
    });
    if (updateRes.error) console.error('Error updating password:', updateRes.error);
    else console.log('Password reset successful');
  } else {
    console.log(`User ${NEW_EMAIL} NOT found. Creating...`);
    const createRes = await request('/auth/v1/admin/users', 'POST', {
      email: NEW_EMAIL,
      password: NEW_PASSWORD,
      email_confirm: true,
      user_metadata: { full_name: 'Divakara' }
    });
    if (createRes.error) {
      console.error('Error creating user:', createRes.error);
      return;
    } else {
      userId = createRes.id;
      console.log('User created successfully with ID:', userId);
    }
  }

  console.log('--- Step 3: Ensuring COMPANY_MASTER exists ---');
  const companyId = 'a1b2c3d4-0000-0000-0000-000000000001';
  const companyRes = await request('/rest/v1/COMPANY_MASTER?id=eq.' + companyId, 'GET');
  if (companyRes.error) {
    console.error('Error checking company (Table missing?):', companyRes.error.message);
  } else if (companyRes.length === 0) {
    console.log('Company missing. Inserting...');
    await request('/rest/v1/COMPANY_MASTER', 'POST', {
      id: companyId,
      company_code: 'CAFE001',
      company_name: 'Gourmet Coffee House',
      city: 'Mumbai',
      has_gst: false
    });
  } else {
    console.log('Company exists');
  }

  console.log('--- Step 4: Ensuring USER_MASTER profile exists ---');
  const profileRes = await request('/rest/v1/USER_MASTER?id=eq.' + userId, 'GET');
  if (profileRes.error) {
    console.error('Error checking profile (Table missing?):', profileRes.error.message);
  } else if (profileRes.length === 0) {
    console.log('Profile missing. Inserting...');
    const pInsert = await request('/rest/v1/USER_MASTER', 'POST', {
      id: userId,
      company_id: companyId,
      employee_code: 'EMP001',
      full_name: 'Divakara',
      username: 'divakara',
      role: 'ADMIN',
      email: NEW_EMAIL
    });
    if (pInsert && pInsert.error) console.error('Error inserting profile:', pInsert.error);
    else console.log('Profile created');
  } else {
    console.log('Profile exists');
  }

  console.log('--- DONE ---');
}

fix();
