# Sample Audio Files


For full athan recitations:

1. **Download from Islamic websites:**
   - [IslamicFinder](https://www.islamicfinder.org/)
   - [Quran.com](https://quran.com/)
   - Various athan apps
   - https://drive.google.com/drive/folders/1NULnpD4eyv0HGhkCqOKUTF9bjfFY8woR?usp=drive_link


2. **Ensure proper ID3 tags:**
```bash
   # View tags
   eyeD3 your_athan.mp3
   
   # Set tags
   eyeD3 --artist "Reciter Name" --title "Athan Title" --album "Collection" your_athan.mp3
```

3. **Place in the correct directory:**
```bash
   cp your_fajr_athans/*.mp3 /var/www/html/files/athan/fajr/
   cp your_regular_athans/*.mp3 /var/www/html/files/athan//prayer/
   cp your_iftar_athans/*.mp3 /var/www/html/files/athan/iftar/
```

## Copyright Notice

Please respect copyright when adding your own athan files. Ensure you have the right to use any recordings you add to your installation.