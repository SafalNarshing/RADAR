const express = require('express');
const app = express();
const PORT = 3000;

// Middleware to parse incoming JSON payloads
app.use(express.json());

// Base route handler
app.get('/', (req, res) => {
    res.send('Hello World! Your Express server is working.');
});

// Start listening for network traffic
app.listen(PORT, () => {
    console.log(`Server running smoothly at http://localhost:${PORT}`);
});
