/// <reference types="astro/client" />

declare namespace App {
  interface Locals {
    accessToken?: string;
    member?: import('./features/access/domain/membership').Membership;
  }
}
