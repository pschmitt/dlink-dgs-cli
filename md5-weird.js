const http = require('http');
const https = require('https');

const args = process.argv.slice(2); // Skip the first two elements

// Default values
let hostname = '10.5.0.6';
let port = 80;
let suffix = '_http';
let stringToHash = '';
let useHttps = false;

// Parse arguments
for (let i = 0; i < args.length; i++) {
    const val = args[i];
    switch (val) {
        case '--hostname':
            if (args[i + 1]) {
                hostname = args[i + 1];
                i++; // Skip next argument since it's part of the current flag
            }
            break;
        case '--port':
            if (args[i + 1]) {
                port = args[i + 1];
                i++; // Skip next argument since it's part of the current flag
            }
            break;
        case '--tls':
        case '--https':
            useHttps = true;
            break;
        case '--suffix':
            if (args[i + 1]) {
                suffix = args[i + 1];
                i++; // Skip next argument since it's part of the current flag
            }
            break;
        default:
            stringToHash = val; // Assume any other argument is the string to hash
            break;
    }
}

// Construct URL
const protocol = useHttps ? 'https' : 'http';
const url = `${protocol}://${hostname}:${port}/js/mm.js`;

// Determine protocol module to use
const protocolModule = useHttps ? https : http;

protocolModule.get(url, (res) => {
    let data = '';

    // A chunk of data has been received.
    res.on('data', (chunk) => {
        data += chunk;
    });

    // The whole response has been received.
    res.on('end', () => {
        try {
            eval(data);
            console.log(md5(stringToHash + suffix));
        } catch (e) {
            console.error('Error executing the remote JS file:', e);
        }
    });

}).on("error", (err) => {
    console.log(`Error: ${err.message}`);
});
