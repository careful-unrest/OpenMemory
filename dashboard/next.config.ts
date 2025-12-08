import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'standalone',
  images: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'cdn.spectrumdevs.com',
        pathname: '/**',
      },
    ],
  },
};

export default nextConfig;
