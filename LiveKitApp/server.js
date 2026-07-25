const express = require('express');
const path = require('path');
const { AccessToken } = require('livekit-server-sdk');

const app = express();
const PORT = 3000;

const apiKey = 'devkey';
const apiSecret = 'secret';

// Serve the index.html file
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// GET TOKEN ENDPOINT: Called by the Flutter client to obtain a LiveKit token
app.get('/api/getToken', async (req, res) => {
    const room = req.query.room;
    const user = req.query.user;
    if (!room || !user) {
        return res.status(400).json({ error: 'Missing room or user parameter' });
    }
    const token = await generateLiveKitToken(room, user);
    res.json({
        token: token,
        wsUrl: 'ws://localhost:7880'
    });
});

// SMART ENDPOINT: Automatically detects whatever Pinggy URL is currently active!
app.get('/create-call', async (req, res) => {
    // 1. Detect the protocol (http or https) and the current active domain name
    const protocol = req.secure || req.headers['x-forwarded-proto'] === 'https' ? 'https' : 'http';
    const currentHost = req.headers.host; 
    const currentPublicUrl = `${protocol}://${currentHost}`;

    // 2. Generate a unique random room name
    const roomName = 'room-' + Math.random().toString(36).substring(2, 7);
    
    // 3. Generate individual tokens (await because toJwt() is async in SDK v2.x)
    const tokenA = await generateLiveKitToken(roomName, 'Host');
    const tokenB = await generateLiveKitToken(roomName, 'Guest');

    // 4. Dynamically assemble the links using the detected Pinggy URL
    const hostLink = `${currentPublicUrl}/?room=${roomName}&token=${tokenA}`;
    const guestInviteLink = `${currentPublicUrl}/?room=${roomName}&token=${tokenB}`;

    // Send the dashboard UI back to the browser
    res.send(`
        <body style="font-family:sans-serif; text-align:center; background:#121212; color:white; padding-top:50px;">
            <h2>📞 Call Created Successfully!</h2>
            <p style="color: #4caf50;">Detected Active Tunnel: <code>${currentPublicUrl}</code></p>
            <div style="margin: 30px auto; max-width: 500px; background:#222; padding:20px; border-radius:8px;">
                <p><strong>Step 1:</strong> Join your own meeting channel:</p>
                <a href="${hostLink}" style="color:#4caf50; font-weight:bold; font-size: 18px;">👉 Click Here to Join Call</a>
            </div>
            <div style="margin: 30px auto; max-width: 500px; background:#222; padding:20px; border-radius:8px;">
                <p><strong>Step 2:</strong> Copy this link and send it to your friend:</p>
                <input type="text" value="${guestInviteLink}" id="inviteUrl" style="width:90%; padding:10px; text-align:center;" readonly>
                <br><br>
                <button onclick="navigator.clipboard.writeText(document.getElementById('inviteUrl').value); alert('Link copied!')" style="padding:10px 20px; cursor:pointer; background: #007bff; color: white; border: none; border-radius: 4px;">Copy Invite Link</button>
            </div>
        </body>
    `);
});

async function generateLiveKitToken(roomName, participantIdentity) {
    const at = new AccessToken(apiKey, apiSecret, {
        identity: participantIdentity,
        ttl: '2h',
    });
    at.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
    return await at.toJwt();
}

app.listen(PORT, () => {
    console.log(`\n🚀 Smart Web Server is active on port ${PORT}!`);
    console.log(`🔒 Open your Pinggy tunnel to generate external shareable links.\n`);
});