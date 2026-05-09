import pymupdf

# Extract OV7670 datasheet
doc = pymupdf.open(r'w:\work\University\Year 2\HWSyn\Final_Project\resources\OV7670_2006.pdf')
text = ''
for i in range(len(doc)):
    text += f'\n--- PAGE {i+1} ---\n'
    text += doc[i].get_text()
with open(r'w:\work\University\Year 2\HWSyn\Final_Project\resources\ov7670_extracted.txt', 'w', encoding='utf-8') as f:
    f.write(text)
print(f'OV7670: Extracted {len(text)} chars from {len(doc)} pages')

# Extract SCCB spec
doc2 = pymupdf.open(r'w:\work\University\Year 2\HWSyn\Final_Project\resources\SCCBSpec_AN.pdf')
text2 = ''
for i in range(len(doc2)):
    text2 += f'\n--- PAGE {i+1} ---\n'
    text2 += doc2[i].get_text()
with open(r'w:\work\University\Year 2\HWSyn\Final_Project\resources\sccb_extracted.txt', 'w', encoding='utf-8') as f:
    f.write(text2)
print(f'SCCB: Extracted {len(text2)} chars from {len(doc2)} pages')
