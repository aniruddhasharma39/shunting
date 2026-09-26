# Cloudinary Setup for Device Registration

To ensure the device and SIM image upload functionality works flawlessly on Vercel, you need to configure a Cloudinary account and provide the credentials to your backend via environment variables.

Follow these steps to configure Cloudinary for file uploads:

### 1. Create a Cloudinary Account
1. Go to [Cloudinary](https://cloudinary.com/) and sign up for a free account if you don't already have one.
2. Log in to your Cloudinary Management Console.

### 2. Get Your Credentials
1. On your Cloudinary Dashboard, navigate to the **Programmable Media** section.
2. Click on **Dashboard**.
3. Under the **Account Details** section, you will see your credentials:
   - **Cloud Name**
   - **API Key**
   - **API Secret**
4. Keep these safe, as you will need to add them to your Vercel deployment.

### 3. Add Environment Variables to Vercel
Go to your Vercel Dashboard for the backend project (`shunting-lemon`):
1. Go to **Settings** -> **Environment Variables**.
2. Add the following keys and values:
   - `CLOUDINARY_CLOUD_NAME` (from step 2)
   - `CLOUDINARY_API_KEY` (from step 2)
   - `CLOUDINARY_API_SECRET` (from step 2)

### 4. Final Redeployment
If your Vercel project doesn't deploy automatically when env vars are added, trigger a redeploy from the Vercel dashboard.

Once this is complete, the image upload system will be 100% operational and images will securely host on Cloudinary and load blazingly fast in the app.
