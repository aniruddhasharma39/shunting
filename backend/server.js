const express = require('express');
const cors = require('cors');
require('dotenv').config();

const authRoutes = require('./routes/authRoutes');
const reportRoutes = require('./routes/reportRoutes');
const yardRoutes = require('./routes/yardRoutes');
const deviceRoutes = require('./routes/deviceRoutes');
const iotRoutes = require('./routes/iotRoutes');
const dashboardRoutes = require('./routes/dashboardRoutes');
const sessionRoutes = require('./routes/sessionRoutes');
const deviceRegistryRoutes = require('./routes/deviceRegistryRoutes');
const awsIotBridge = require('./services/awsIotBridge');

const app = express();

// Middleware
app.use(cors());
app.use(express.json()); // Allows parsing of JSON request bodies
app.use('/uploads', express.static('uploads')); // Serve uploaded files

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/yards', yardRoutes);
app.use('/api/devices', deviceRoutes);
app.use('/api/device-registry', deviceRegistryRoutes);
app.use('/api/iot', iotRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/sessions', sessionRoutes);

// Base route for testing
app.get('/', (req, res) => {
  res.send('SafeShunt Backend API is running');
});

// Global error handler middleware
app.use((err, req, res, next) => {
  console.error('Unhandled request error:', err);
  res.status(500).json({ success: false, message: 'Internal server error', error: err.message });
});

// Prevent server crash from unhandled promises
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception thrown:', err);
});

// Start Server
const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  awsIotBridge.initialize();
});
