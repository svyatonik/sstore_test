#!/bin/bash
# return: "0x04bfc447952f4d1818a49f6b30bbf42ef26d6a25844ea2d11cb93a8a7ac385de6c162edbd1c2b785061456b35075e620bd3991a7df5967a594c87bd199caf90810a463e02da8b3415d471495ad37fa069d287a830e72f27b565fc3f28b5888c1e16c4435ef801bc6ffd680767b82a3102268f53796b9fa61117138bd5c72bb5e0556d6d9e17ce850d499e344ae68c1b04cbde3077e9d2a4ba9cceb057d2d609133c479aa891adf38c3511424c2cbc86764"
curl -v -X POST http://localhost:8082/0000000000000000000000000000000000000000000000000000000000000002/8607288d0b87f3ad51d541fa010faff747fa9ae4dbe45c07e5ab6ab79915bcc121d6c407ea75b19e3a27a5a193b310a42bbbbabca2da59c0b582071c33a2de1501/${1:-1}
