\# Sample Artwork



\## Using Custom Artwork



1\. \*\*Recommended specifications:\*\*

&nbsp;  - Format: JPEG or PNG

&nbsp;  - Resolution: 1920x1080 (Full HD) or higher

&nbsp;  - File size: Under 2MB for faster loading

&nbsp;  - Aspect ratio: 16:9 for most displays



2\. \*\*Finding Islamic artwork:\*\*

&nbsp;  - \[Unsplash](https://unsplash.com/s/photos/mosque) (Free to use)

&nbsp;  - \[Pexels](https://www.pexels.com/search/mosque/) (Free to use)

&nbsp;  - \[Wikimedia Commons](https://commons.wikimedia.org/) (Various licenses)

&nbsp;  - https://drive.google.com/drive/folders/1NULnpD4eyv0HGhkCqOKUTF9bjfFY8woR?usp=drive\_link

&nbsp;  - Your own photography of local mosques



3\. \*\*Install your artwork:\*\*

```bash

&nbsp;  cp your\_mosque\_image.jpg /var/www/html/files/athan/Mohamed\_Ali\_Mosque.jpg

&nbsp;  cp your\_iftar\_image.jpg /var/www/html/files/athan/Iftar.jpg

```



4\. \*\*Update configuration:\*\*

&nbsp;  Edit `/etc/athan-automation/config.ini`:

```ini

&nbsp;  athan\_art\_url = http://your-ip/athan/Mohamed\_Ali\_Mosque.jpg

&nbsp;  iftar\_art\_url = http://your-ip/athan/Iftar.jpg

```



\## Copyright Notice



When using your own images, ensure you have the rights to use them. Always provide proper attribution for Creative Commons licensed images.

